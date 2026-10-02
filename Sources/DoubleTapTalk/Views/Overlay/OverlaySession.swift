import Foundation

/// Which layout the capsule uses.
///
/// The two continuous-dictation modes have opposite jobs. A one-shot dictation
/// is over in seconds, so the capsule is the transcript: elastic width, up to
/// four lines, then gone. A relay session stays on screen for minutes, the
/// user's document is the real output, so the capsule becomes a fixed-height
/// status HUD: one dimmed line of in-progress words plus a segment/status
/// column — and it must never grow into the typing area.
enum OverlayLayout: Equatable {
    /// Transient one-shot presentation.
    case focused
    /// Persistent continuous-dictation HUD.
    case session
}

/// Pure bookkeeping for one continuous-dictation session: what the user said,
/// what actually landed in the document, and what did not. The overlay owns one
/// of these so the AppDelegate never has to aggregate anything.
struct RelaySessionLedger {
    /// Segments whose work started (each idle rotation, plus the final one).
    private(set) var segmentsStarted = 0
    private(set) var segmentsInserted = 0
    private(set) var segmentsSkipped = 0
    /// Failures for the whole session — reported in the closing summary.
    private(set) var segmentsFailed = 0
    private(set) var characters = 0

    /// Failures still waiting to be acknowledged. Cleared by the next
    /// successful insertion: the capsule shows a ledger chip until the user has
    /// seen at least one segment land after the problem.
    private(set) var unacknowledgedFailures = 0

    mutating func noteSegmentStarted() {
        segmentsStarted += 1
    }

    mutating func noteInserted(characters: Int) {
        segmentsInserted += 1
        self.characters += max(characters, 0)
        unacknowledgedFailures = 0
    }

    mutating func noteSkipped() {
        segmentsSkipped += 1
    }

    mutating func noteFailed() {
        segmentsFailed += 1
        unacknowledgedFailures += 1
    }

    mutating func reset() {
        self = RelaySessionLedger()
    }
}

/// The receipt shown when a continuous-dictation session ends: what landed,
/// how much, how long it took, and what the user should know about.
struct OverlaySessionSummary: Equatable {
    let segments: Int
    let characters: Int
    let duration: TimeInterval
    let skipped: Int
    let failed: Int

    func text(language: OverlayLanguage) -> String {
        let clock = OverlayMetrics.sessionDurationLabel(seconds: Int(duration.rounded()))
        var parts = [OverlaySessionCopy.insertedCount(segments, language: language),
                     OverlaySessionCopy.characterCount(characters, language: language),
                     clock]
        if skipped > 0 {
            parts.append(OverlaySessionCopy.skippedCount(skipped, language: language))
        }
        if failed > 0 {
            parts.append(OverlaySessionCopy.failedCount(failed, language: language))
        }
        return parts.joined(separator: OverlaySessionCopy.separator(language: language))
    }
}

/// Every user-facing string the session HUD can show. Localized in one place —
/// the AppDelegate never supplies overlay copy.
enum OverlaySessionCopy {

    /// How long a segment receipt stays up before the status column returns to
    /// its resting state.
    static let receiptDuration: TimeInterval = 1.2
    /// An empty segment is a non-event; it gets a shorter nod.
    static let skippedReceiptDuration: TimeInterval = 0.8
    /// How long the session summary holds before the capsule leaves.
    static let summaryDuration: TimeInterval = 1.5

    static func separator(language: OverlayLanguage) -> String { " · " }

    static func segmentIndex(_ index: Int, language: OverlayLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "第 \(index) 段"
        case .english: return "Seg \(index)"
        }
    }

    static func uploading(language: OverlayLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "识别中…"
        case .english: return "Uploading…"
        }
    }

    static func polishing(language: OverlayLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "润色中…"
        case .english: return "Polishing…"
        }
    }

    /// Shown right after a segment lands in the document.
    static func inserted(characters: Int, language: OverlayLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "✓ 已插入 · \(characters) 字"
        case .english: return "✓ Inserted · \(characters) chars"
        }
    }

    static func skipped(language: OverlayLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "无语音，已跳过"
        case .english: return "No speech · skipped"
        }
    }

    /// Persistent chip: segments that were recognized but never inserted. The
    /// user must be able to tell "it heard me" from "it saved my words".
    static func failureLedger(_ count: Int, language: OverlayLanguage) -> String {
        switch language {
        case .simplifiedChinese: return count == 1 ? "⚠︎ 1 段未插入" : "⚠︎ \(count) 段未插入"
        case .english: return count == 1 ? "⚠︎ 1 not inserted" : "⚠︎ \(count) not inserted"
        }
    }

    static func insertedCount(_ count: Int, language: OverlayLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "\(count) 段"
        case .english: return "\(count) seg"
        }
    }

    static func characterCount(_ count: Int, language: OverlayLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "\(count) 字"
        case .english: return "\(count) chars"
        }
    }

    static func skippedCount(_ count: Int, language: OverlayLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "跳过 \(count) 段"
        case .english: return "\(count) skipped"
        }
    }

    static func failedCount(_ count: Int, language: OverlayLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "\(count) 段未插入"
        case .english: return "\(count) not inserted"
        }
    }

    /// Continuous-dictation menu bar header.
    static func relayHeader(segments: Int, clock: String, language: OverlayLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "连续听写中 · 第 \(segments) 段 · \(clock)"
        case .english: return "Continuous dictation · seg \(segments) · \(clock)"
        }
    }

    static func relayFinalizing(language: OverlayLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "正在收尾 · 最后一段"
        case .english: return "Finishing · last segment"
        }
    }

    static func endRelaySession(language: OverlayLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "结束连续听写"
        case .english: return "End Continuous Dictation"
        }
    }
}
