import Foundation
import Speech
import AVFoundation

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

    static func locale(for languageCode: String?) -> Locale {
        guard let code = languageCode, code != "auto" else {
            return Locale.current
        }
        if let identifier = supported[code] {
            return Locale(identifier: identifier)
        }
        // Valid extended identifiers (e.g. "en-GB", "zh-Hant_TW") pass through
        // so power users can use any locale SFSpeechRecognizer supports. Garbage
        // two-letter codes fall back to the system locale.
        if code.contains("-") || code.contains("_") {
            return Locale(identifier: code)
        }
        return Locale.current
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

    private var inputFormat: AVAudioFormat?

    // MARK: - Permission

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Lifecycle

    func start(language code: String?) throws {
        let locale = SpeechLocaleMapper.locale(for: code)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            let message = "Speech recognition is not supported for \(locale.identifier). Download the language in System Settings > Keyboard > Dictation."
            onError?(message)
            throw ASRError.transcriptionFailed(message)
        }

        transcript.reset()
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        self.recognitionRequest = recognitionRequest

        let inputNode = audioEngine.inputNode
        inputFormat = inputNode.outputFormat(forBus: 0)
        guard let inputFormat = inputFormat else {
            throw ASRError.audioFileError
        }

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            if let error = error {
                logger.warning("Speech recognition error: \(error.localizedDescription)")
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

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            if let rms = self?.rms(of: buffer) {
                self?.onAudioLevel?(rms)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            logger.error("Failed to start audio engine: \(error)")
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
        return text
    }

    // MARK: - Helpers

    private func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else {
            return rmsInt16(of: buffer)
        }
        let frames = Int(buffer.frameLength)
        let data = channelData[0]
        var sum: Double = 0
        for i in 0..<frames {
            let sample = Double(data[i])
            sum += sample * sample
        }
        guard frames > 0 else { return 0 }
        // Normalize RMS (peak 1.0 for float samples) and clamp to 0...1.
        return Float(min(1.0, sqrt(sum / Double(frames)) * 2.0))
    }

    private func rmsInt16(of buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.format.commonFormat == .pcmFormatInt16,
              let raw = buffer.int16ChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        let data = raw[0]
        var sum: Double = 0
        for i in 0..<frames {
            let sample = Double(data[i]) / 32768.0
            sum += sample * sample
        }
        guard frames > 0 else { return 0 }
        return Float(min(1.0, sqrt(sum / Double(frames)) * 2.0))
    }
}