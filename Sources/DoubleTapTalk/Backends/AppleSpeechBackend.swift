import Foundation
import Speech
import AVFoundation
import Carbon

private let logger = FileLogger.shared

/// Pure accumulation of streaming recognition results (testable without AppKit).
/// Distinguishes partial (live) updates from final (committed) results:
/// once a final result arrives, non-final updates no longer affect the text.
struct RecognitionTranscript {
    private var finalText: String?
    private var partialText: String = ""

    /// The best text available right now: the last final result, or the latest partial.
    var currentText: String {
        finalText ?? partialText
    }

    /// Whether a final result has been committed.
    var hasFinal: Bool { finalText != nil }

    mutating func apply(transcript: String, isFinal: Bool) {
        if isFinal {
            finalText = transcript
            partialText = ""
        } else if finalText == nil {
            partialText = transcript
        }
        // Non-final updates after a final result are deliberately ignored.
    }

    mutating func reset() {
        finalText = nil
        partialText = ""
    }
}

/// Reads the active keyboard input source's language (macOS TIS).
/// This is the "input method" heuristic: if you're typing Pinyin, recognition
/// should follow in Chinese; if the keyboard is ABC/US, recognition is English.
/// NOTE: must be called on the main thread.
enum InputMethodLanguage {
    static func currentLanguageCode() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let langs = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return nil
        }
        let languages = Unmanaged<CFArray>.fromOpaque(langs).takeUnretainedValue() as? [String]
        return languages?.first
    }
}

/// Maps the app's language codes ("auto", "zh", "en", ...) to the locale
/// identifiers accepted by SFSpeechRecognizer (pure, testable).
enum SpeechLocaleMapper {
    private static let supported: [String: String] = [
        "en": "en-US",
        "zh": "zh-CN",
        "es": "es-ES",
        "fr": "fr-FR",
        "de": "de-DE",
        "ja": "ja-JP",
        "ko": "ko-KR",
    ]

    /// Dictation locales we can fall back to (a subset of SFSpeechRecognizer.supportedLocales()).
    private static let fallbackCandidates = [
        "en-US", "en-GB", "en-AU", "en-CA", "en-IN", "en-SG",
        "zh-CN", "zh-HK", "zh-TW", "ja-JP", "ko-KR",
        "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR", "ru-RU",
    ]

    static func locale(for languageCode: String?, inputMethodLanguage: String? = nil) -> Locale {
        if let code = languageCode, code != "auto" {
            if let identifier = supported[code] {
                return Locale(identifier: identifier)
            }
            // Valid extended identifiers (e.g. "en-GB", "zh-Hant_TW") pass through
            // so power users can use any locale SFSpeechRecognizer supports.
            if code.contains("-") || code.contains("_") {
                return Locale(identifier: code)
            }
            return bestLocale(identifier: code)
        }
        // "auto": the active input method decides (Chinese IME → Chinese,
        // English keyboard → English); system locale is the fallback.
        if let imLang = inputMethodLanguage, !imLang.isEmpty {
            return bestLocale(identifier: imLang)
        }
        return bestLocale(for: Locale.current)
    }

    /// Maps a system locale to a REAL dictation locale. This is critical:
    /// "auto" used to pass Locale.current straight through, which on machines
    /// with mismatched language/region (e.g. "en_CN") made SFSpeechRecognizer
    /// fail with a "Corrupt" error and transcribe nothing.
    private static func bestLocale(for current: Locale) -> Locale {
        let normalized = current.identifier.replacingOccurrences(of: "_", with: "-")
        if fallbackCandidates.contains(normalized) {
            return Locale(identifier: normalized)
        }
        guard let lang = (current.language.languageCode?.identifier.lowercased()) else {
            return Locale(identifier: "en-US")
        }
        if let match = fallbackCandidates.first(where: { $0.hasPrefix(lang + "-") }) {
            return Locale(identifier: match)
        }
        return lang == "zh" ? Locale(identifier: "zh-CN") : Locale(identifier: "en-US")
    }

    private static func bestLocale(identifier code: String) -> Locale {
        let normalized = code.replacingOccurrences(of: "_", with: "-")
        if fallbackCandidates.contains(normalized) {
            return Locale(identifier: normalized)
        }
        let lower = normalized.lowercased()
        if lower.contains("hant") {
            return Locale(identifier: "zh-TW")
        }
        if lower.contains("hans") || lower.hasPrefix("zh") {
            return Locale(identifier: "zh-CN")
        }
        let lang = lower.components(separatedBy: "-").first ?? ""
        if let match = fallbackCandidates.first(where: { $0.hasPrefix(lang + "-") }) {
            return Locale(identifier: match)
        }
        return Locale(identifier: "en-US")
    }
}

/// Resolves a locale (with Apple's fallback chain) and creates an
/// SFSpeechRecognizer for it. Shared by the single-shot backend and the
/// continuous dictation session.
enum SpeechRecognizerFactory {
    static func make(locale code: String?, inputMethodLanguage: String?) -> (recognizer: SFSpeechRecognizer, locale: Locale)? {
        var locale = SpeechLocaleMapper.locale(for: code, inputMethodLanguage: inputMethodLanguage)
        var recognizer = SFSpeechRecognizer(locale: locale)
        if recognizer == nil {
            let supported = SFSpeechRecognizer.supportedLocales()
            if let lang = locale.language.languageCode?.identifier,
               let match = supported.first(where: { $0.language.languageCode?.identifier == lang }) {
                locale = match
                recognizer = SFSpeechRecognizer(locale: match)
            } else {
                locale = Locale(identifier: "en-US")
                recognizer = SFSpeechRecognizer(locale: locale)
            }
        }
        guard let recognizer = recognizer else { return nil }
        return (recognizer, locale)
    }
}

/// RMS audio level (0...1) for a tap buffer, handling Float32 and Int16 PCM.
enum AudioLevel {
    static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              let mData = buffer.audioBufferList.pointee.mBuffers.mData else {
            return rmsInt16(of: buffer)
        }
        let frames = Int(buffer.frameLength)
        let data = mData.assumingMemoryBound(to: Float.self)
        var sum: Double = 0
        for i in 0..<frames {
            let sample = Double(data[i])
            sum += sample * sample
        }
        guard frames > 0 else { return 0 }
        // Normalize RMS (peak 1.0 for float samples) and clamp to 0...1.
        return Float(min(1.0, sqrt(sum / Double(frames)) * 2.0))
    }

    private static func rmsInt16(of buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.format.commonFormat == .pcmFormatInt16,
              let mData = buffer.audioBufferList.pointee.mBuffers.mData else { return 0 }
        let frames = Int(buffer.frameLength)
        let data = mData.assumingMemoryBound(to: Int16.self)
        var sum: Double = 0
        for i in 0..<frames {
            let sample = Double(data[i]) / 32768.0
            sum += sample * sample
        }
        guard frames > 0 else { return 0 }
        return Float(min(1.0, sqrt(sum / Double(frames)) * 2.0))
    }
}

/// On-device streaming speech recognition using Apple's Speech framework.
/// Delivers live partial text + audio level callbacks while recording, and
/// returns the final transcription on stop(). No network, no API key needed.
final class AppleSpeechBackend: NSObject, SFSpeechRecognizerDelegate {
    var onPartialText: ((String) -> Void)?
    var onFinalText: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onError: ((String) -> Void)?

    var name: String { "Apple (On-Device)" }

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var transcript = RecognitionTranscript()

    /// WAV file of the captured audio (16 kHz mono), finalized on `stop()`.
    /// nil when nothing was recorded or recording failed to start.
    private(set) var recordingFileURL: URL?
    private var recorder: RecordingFileWriter?

    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var converterFormat: AVAudioFormat?

    // MARK: - Permission

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Lifecycle

    func start(language code: String?, inputMethodLanguage: String? = nil) throws {
        guard let pair = SpeechRecognizerFactory.make(locale: code, inputMethodLanguage: inputMethodLanguage) else {
            let message = "Speech recognition is not supported for \(SpeechLocaleMapper.locale(for: code, inputMethodLanguage: inputMethodLanguage).identifier). Download the language in System Settings > Keyboard > Dictation."
            onError?(message)
            throw PipelineError.transcriptionFailed(message)
        }
        let recognizer = pair.recognizer
        let locale = pair.locale

        transcript.reset()
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        self.recognitionRequest = recognitionRequest

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let error = error {
                let ns = error as NSError
                logger.warning("Speech recognition error: \(error.localizedDescription) (domain=\(ns.domain) code=\(ns.code))")
                if result == nil {
                    self.onError?(error.localizedDescription)
                }
                return
            }
            guard let result = result else { return }
            let text = result.bestTranscription.formattedString
            let isFinal = result.isFinal
            self.transcript.apply(transcript: text, isFinal: isFinal)
            if isFinal {
                self.onFinalText?(text)
            } else {
                self.onPartialText?(text)
            }
        }

        let inputNode = audioEngine.inputNode
        inputFormat = inputNode.outputFormat(forBus: 0)
        guard let inputFormat = inputFormat else {
            throw PipelineError.audioFileError
        }

        // CRITICAL: SFSpeechRecognizer streaming on macOS expects 16kHz mono.
        // Many Macs deliver 44.1/48kHz stereo from the mic, which makes the
        // recognizer fail with "Corrupt" and transcribe nothing. Convert always.
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw PipelineError.audioFileError
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        converterFormat = targetFormat

        // Save the same 16 kHz mono stream to a WAV file ONLY when cloud
        // transcription is enabled — the file exists purely to be uploaded, so
        // with ASR off no audio ever touches disk. Best-effort: a recording
        // failure must never stop recognition.
        if ASRSettings.current().enabled,
           let writer = RecordingFileWriter(directory: RecordingFileWriter.defaultDirectory()) {
            do {
                try writer.open()
                recorder = writer
            } catch {
                logger.warning("Could not open recording file: \(error)")
            }
        }

        let request = recognitionRequest
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.onAudioLevel?(AudioLevel.rms(of: buffer))
            self.appendToRecognition(buffer, request: request)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            logger.error("Failed to start audio engine: \(error)")
            recorder?.cancel()
            throw error
        }

        logger.info("Apple streaming recognition started (locale: \(locale.identifier))")
    }

    /// Ends the session and returns the best transcription available
    /// (the final result, if delivered, else the last partial).
    func stop() async -> String {
        logger.info("Stopping Apple streaming recognition...")
        recognitionTask?.finish()

        // Give SFSpeechRecognizer a short window to commit the final result.
        try? await Task.sleep(nanoseconds: 700_000_000)

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil

        let text = transcript.currentText
        logger.info("Apple recognition result: '\(text)'")

        // Finalize the recorded audio. Segments with no recognized words are
        // skipped entirely — the blank recording is deleted so it is never kept
        // or sent to cloud ASR.
        let hasWords = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasWords {
            recordingFileURL = recorder?.finish()
        } else {
            recorder?.cancel()
            recordingFileURL = nil
        }
        recorder = nil

        return text
    }

    // MARK: - Helpers

    /// Feeds audio to the recognition request, converting to 16kHz mono first
    /// (the format SFSpeechRecognizer needs on macOS). Skips conversion only
    /// when the tap already delivers 16kHz mono.
    private func appendToRecognition(_ buffer: AVAudioPCMBuffer, request: SFSpeechAudioBufferRecognitionRequest) {
        guard let converter, let targetFormat = converterFormat else {
            request.append(buffer)
            recorder?.append(buffer)
            return
        }
        if abs(buffer.format.sampleRate - 16000) < 0.5 && buffer.format.channelCount == 1 {
            request.append(buffer)
            recorder?.append(buffer)
            return
        }
        // The converter consumes input synchronously inside this tap callback,
        // so it's safe to hand it the tap buffer directly (the engine only
        // recycles it after the callback returns).
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) / buffer.format.sampleRate * targetFormat.sampleRate) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return }

        var delivered = false
        let status = converter.convert(to: out, error: nil) { _, inputStatus in
            if delivered {
                inputStatus.pointee = .noDataNow
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if out.frameLength > 0, status == .haveData || status == .inputRanDry {
            request.append(out)
            recorder?.append(out)
        }
    }
}