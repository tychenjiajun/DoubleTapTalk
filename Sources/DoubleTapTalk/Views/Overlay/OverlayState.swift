import Foundation

/// The pipeline stage the recording overlay is currently rendering. Each state
/// maps to exactly one visual language (see `OverlayStyle`), so the capsule can
/// never look "frozen but alive" the way a waveform stuck on a stale audio
/// level did.
enum OverlayState: Equatable {
    /// Live on-device transcription; the bars track the real audio level.
    case listening
    /// Cloud ASR is replacing the Apple result.
    case transcribing
    /// The LLM polish pass is running.
    case polishing
    /// The final text is being revealed before it is injected.
    case success
    /// Nothing was recognized.
    case empty
    /// A stage failed.
    case error
}

/// Language of the overlay's status strings.
enum OverlayLanguage: Equatable {
    case simplifiedChinese
    case english
}

/// Pure, AppKit-free state → visuals mapping (unit tested in
/// `OverlayStateTests`). Keeping it free of `NSImage`/`NSColor` lets the whole
/// visual language be asserted without a window server.
enum OverlayStyle {

    /// How the fixed-width activity slot at the capsule's leading edge renders.
    enum Waveform: Equatable {
        /// Bars driven by real audio levels.
        case level
        /// Bars driven by a travelling bump: "working, but not listening".
        case indeterminate
        /// A single SF Symbol instead of bars.
        case symbol(String)
    }

    /// Accent applied to the activity slot and the capsule border.
    enum Tint: Equatable {
        case neutral
        case dimmed
        case positive
        case caution
        case critical
    }

    struct Resolved: Equatable {
        let statusText: String
        let waveform: Waveform
        let tint: Tint
        /// When true the capsule shows the carried payload text (live transcript
        /// or final result) and only falls back to `statusText` when empty.
        let prefersText: Bool
        /// True while post-recording work runs — the clock is no longer news.
        let dimsTimer: Bool
    }

    /// The clock stays dimmed until the user has actually been talking for a
    /// while: "0s" is noise, "0:12" is information.
    static let timerRevealSecond = 5

    /// zh-Hans when the system asks for Chinese, English otherwise.
    static func language(preferredLanguages: [String] = Locale.preferredLanguages) -> OverlayLanguage {
        guard let first = preferredLanguages.first?.lowercased() else { return .english }
        return first.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    static func resolve(_ state: OverlayState, language: OverlayLanguage) -> Resolved {
        switch (state, language) {
        case (.listening, .simplifiedChinese):
            return Resolved(statusText: "正在聆听…", waveform: .level, tint: .neutral,
                            prefersText: true, dimsTimer: false)
        case (.listening, .english):
            return Resolved(statusText: "Listening…", waveform: .level, tint: .neutral,
                            prefersText: true, dimsTimer: false)

        case (.transcribing, .simplifiedChinese):
            return Resolved(statusText: "云端识别中…", waveform: .indeterminate, tint: .dimmed,
                            prefersText: false, dimsTimer: true)
        case (.transcribing, .english):
            return Resolved(statusText: "Transcribing…", waveform: .indeterminate, tint: .dimmed,
                            prefersText: false, dimsTimer: true)

        case (.polishing, .simplifiedChinese):
            return Resolved(statusText: "正在润色…", waveform: .indeterminate, tint: .dimmed,
                            prefersText: false, dimsTimer: true)
        case (.polishing, .english):
            return Resolved(statusText: "Polishing…", waveform: .indeterminate, tint: .dimmed,
                            prefersText: false, dimsTimer: true)

        // The result state carries the text itself: the checkmark accents the
        // final wording instead of replacing it.
        case (.success, .simplifiedChinese):
            return Resolved(statusText: "已插入", waveform: .symbol("checkmark"), tint: .positive,
                            prefersText: true, dimsTimer: true)
        case (.success, .english):
            return Resolved(statusText: "Inserted", waveform: .symbol("checkmark"), tint: .positive,
                            prefersText: true, dimsTimer: true)

        case (.empty, .simplifiedChinese):
            return Resolved(statusText: "未识别到语音", waveform: .symbol("mic.slash"), tint: .caution,
                            prefersText: false, dimsTimer: true)
        case (.empty, .english):
            return Resolved(statusText: "No speech detected", waveform: .symbol("mic.slash"), tint: .caution,
                            prefersText: false, dimsTimer: true)

        case (.error, .simplifiedChinese):
            return Resolved(statusText: "出错了 · 再次双按 ⌃ 重试", waveform: .symbol("exclamationmark.triangle.fill"),
                            tint: .critical, prefersText: false, dimsTimer: true)
        case (.error, .english):
            return Resolved(statusText: "Something went wrong · press ⌃ twice to retry",
                            waveform: .symbol("exclamationmark.triangle.fill"),
                            tint: .critical, prefersText: false, dimsTimer: true)
        }
    }
}
