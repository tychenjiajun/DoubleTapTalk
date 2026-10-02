import Foundation
import Speech
import AVFoundation
import Carbon

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
/// SFSpeechRecognizer for it. Used by the continuous dictation session.
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

/// One-shot authorization for Apple's Speech framework — the relay session's
/// only prerequisite.
enum SpeechPermission {
    static func request() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}