import XCTest
@testable import DoubleTapTalk

/// Tests for the continuous-dictation (relay) HUD: the ledger that decides what
/// the user is told, and the session geometry. In this mode the document is the
/// real output, so the capsule's only job is to prove what landed — a silent
/// capsule here reads as "my words are saved" when they are not.
final class RelaySessionLedgerTests: XCTestCase {

    func testCountsRotationsInsertsAndSkips() {
        var ledger = RelaySessionLedger()
        ledger.noteSegmentStarted()
        ledger.noteInserted(characters: 24)
        ledger.noteSegmentStarted()
        ledger.noteSkipped()
        ledger.noteSegmentStarted()
        ledger.noteInserted(characters: 10)

        XCTAssertEqual(ledger.segmentsStarted, 3)
        XCTAssertEqual(ledger.segmentsInserted, 2)
        XCTAssertEqual(ledger.segmentsSkipped, 1)
        XCTAssertEqual(ledger.characters, 34)
        XCTAssertEqual(ledger.segmentsFailed, 0)
    }

    func testFailureIsCountedButNotInserted() {
        var ledger = RelaySessionLedger()
        ledger.noteSegmentStarted()
        ledger.noteFailed()

        XCTAssertEqual(ledger.segmentsFailed, 1, "a failed segment must never count as inserted")
        XCTAssertEqual(ledger.segmentsInserted, 0)
        XCTAssertEqual(ledger.characters, 0)
    }

    func testFailureChipClearsAfterTheNextSuccessfulInsert() {
        var ledger = RelaySessionLedger()
        ledger.noteFailed()
        XCTAssertEqual(ledger.unacknowledgedFailures, 1, "the chip must appear immediately")

        ledger.noteInserted(characters: 5)
        XCTAssertEqual(ledger.unacknowledgedFailures, 0,
                       "once a segment lands the user has seen the system recover")
        XCTAssertEqual(ledger.segmentsFailed, 1, "but the session total still reports it")
    }

    func testFailureChipAccumulatesUntilAcknowledged() {
        var ledger = RelaySessionLedger()
        ledger.noteFailed()
        ledger.noteFailed()
        XCTAssertEqual(ledger.unacknowledgedFailures, 2)
    }

    func testNegativeCharacterCountIsIgnored() {
        var ledger = RelaySessionLedger()
        ledger.noteInserted(characters: -5)
        XCTAssertEqual(ledger.characters, 0)
    }

    func testResetClearsEverything() {
        var ledger = RelaySessionLedger()
        ledger.noteSegmentStarted()
        ledger.noteInserted(characters: 8)
        ledger.noteFailed()
        ledger.reset()

        XCTAssertEqual(ledger.segmentsStarted, 0)
        XCTAssertEqual(ledger.segmentsInserted, 0)
        XCTAssertEqual(ledger.segmentsFailed, 0)
        XCTAssertEqual(ledger.unacknowledgedFailures, 0)
        XCTAssertEqual(ledger.characters, 0)
    }
}

/// Tests for the receipt that closes a continuous-dictation session.
final class OverlaySessionSummaryTests: XCTestCase {

    private func summary(segments: Int = 7,
                         characters: Int = 312,
                         duration: TimeInterval = 102,
                         skipped: Int = 0,
                         failed: Int = 0) -> OverlaySessionSummary {
        OverlaySessionSummary(segments: segments, characters: characters,
                              duration: duration, skipped: skipped, failed: failed)
    }

    func testChineseSummaryReadsAsSegmentsCharactersAndTime() {
        XCTAssertEqual(summary().text(language: .simplifiedChinese), "7 段 · 312 字 · 1:42")
    }

    func testEnglishSummaryReadsAsSegmentsCharactersAndTime() {
        XCTAssertEqual(summary().text(language: .english), "7 seg · 312 chars · 1:42")
    }

    func testCleanSummaryOmitsProblemsEntirely() {
        // No skipped/failed segments means no scary bookkeeping in the common case.
        XCTAssertFalse(summary().text(language: .english).contains("skipped"))
        XCTAssertFalse(summary().text(language: .english).contains("not inserted"))
        XCTAssertFalse(summary().text(language: .simplifiedChinese).contains("未插入"))
    }

    func testFailedSegmentsAreCalledOut() {
        XCTAssertEqual(summary(failed: 1).text(language: .simplifiedChinese),
                       "7 段 · 312 字 · 1:42 · 1 段未插入")
        XCTAssertTrue(summary(failed: 3).text(language: .english).hasSuffix("3 not inserted"))
    }

    func testSkippedSegmentsAreCalledOut() {
        XCTAssertTrue(summary(skipped: 2).text(language: .simplifiedChinese).contains("跳过 2 段"))
        XCTAssertTrue(summary(skipped: 2).text(language: .english).hasSuffix("2 skipped"))
    }

    func testEmptySessionStillProducesAReceipt() {
        let text = summary(segments: 0, characters: 0, duration: 3).text(language: .simplifiedChinese)
        XCTAssertEqual(text, "0 段 · 0 字 · 0:03")
    }

    func testLongSessionDurationIsNotTruncated() {
        XCTAssertTrue(summary(duration: 3_723).text(language: .english).hasSuffix("62:03"))
    }

    func testChineseAndEnglishSummariesDiffer() {
        XCTAssertNotEqual(summary().text(language: .simplifiedChinese),
                          summary().text(language: .english))
    }
}

/// Tests for the localized session HUD copy.
final class OverlaySessionCopyTests: XCTestCase {

    func testEveryCopyIsPresentAndTranslated() {
        let strings: [(OverlayLanguage) -> String] = [
            { OverlaySessionCopy.segmentIndex(3, language: $0) },
            { OverlaySessionCopy.uploading(language: $0) },
            { OverlaySessionCopy.polishing(language: $0) },
            { OverlaySessionCopy.inserted(characters: 24, language: $0) },
            { OverlaySessionCopy.skipped(language: $0) },
            { OverlaySessionCopy.failureLedger(2, language: $0) },
            { OverlaySessionCopy.endRelaySession(language: $0) },
            { OverlaySessionCopy.relayHeader(segments: 3, clock: "1:42", language: $0) },
            { OverlaySessionCopy.relayFinalizing(language: $0) }
        ]
        for make in strings {
            XCTAssertFalse(make(.simplifiedChinese).isEmpty)
            XCTAssertFalse(make(.english).isEmpty)
            XCTAssertNotEqual(make(.simplifiedChinese), make(.english),
                              "a Chinese user must not get English HUD copy")
        }
    }

    func testSegmentIndexIsSingularNotPluralized() {
        XCTAssertEqual(OverlaySessionCopy.failureLedger(1, language: .english), "⚠︎ 1 not inserted")
        XCTAssertEqual(OverlaySessionCopy.failureLedger(4, language: .english), "⚠︎ 4 not inserted")
        XCTAssertEqual(OverlaySessionCopy.failureLedger(1, language: .simplifiedChinese), "⚠︎ 1 段未插入")
    }

    func testInsertedReceiptCarriesTheCharacterCount() {
        XCTAssertTrue(OverlaySessionCopy.inserted(characters: 24, language: .english).contains("24"))
        XCTAssertTrue(OverlaySessionCopy.inserted(characters: 24, language: .simplifiedChinese).contains("24"))
    }

    func testRelayHeaderCarriesSegmentCountAndClock() {
        let header = OverlaySessionCopy.relayHeader(segments: 3, clock: "1:42", language: .english)
        XCTAssertTrue(header.contains("3"))
        XCTAssertTrue(header.contains("1:42"))
    }

    func testReceiptDurationsAreShortEnoughToStayOutOfTheWay() {
        XCTAssertLessThanOrEqual(OverlaySessionCopy.receiptDuration, 1.5)
        XCTAssertLessThanOrEqual(OverlaySessionCopy.skippedReceiptDuration,
                                 OverlaySessionCopy.receiptDuration)
        XCTAssertGreaterThanOrEqual(OverlaySessionCopy.summaryDuration, 1.0,
                                    "the closing receipt must be readable")
    }
}

/// Tests for the session HUD geometry. A capsule that lives for minutes must
/// never grow into the typing area, and it must never sit wider than the
/// one-shot capsule for the same words.
final class OverlaySessionLayoutTests: XCTestCase {

    func testCompactIdleThresholdNeverBeatsTheSegmentRotation() {
        // A pause long enough to become a segment must not also collapse the
        // HUD — the user would lose the receipt they are waiting for.
        for threshold in [1.0, 2.0, 3.0, 5.0, 10.0] {
            XCTAssertGreaterThanOrEqual(OverlayMetrics.compactIdleThreshold(idleThreshold: threshold),
                                        threshold * 2)
        }
        XCTAssertEqual(OverlayMetrics.compactIdleThreshold(idleThreshold: 3), 8)
        XCTAssertEqual(OverlayMetrics.compactIdleThreshold(idleThreshold: 10), 20)
    }

    func testSessionCapsuleIsShorterThanAWrappedCapsule() {
        let wrapped = OverlayMetrics.capsuleHeight(for: String(repeating: "a", count: 300))
        XCTAssertEqual(OverlayMetrics.sessionHeight, OverlayMetrics.baseHeight)
        XCTAssertLessThan(OverlayMetrics.sessionHeight, wrapped,
                          "the persistent HUD must not grow to four lines")
        XCTAssertLessThan(OverlayMetrics.sessionCompactHeight, OverlayMetrics.sessionHeight)
    }

    func testCompactPillSitsAtTheLayoutsHardFloor() {
        // Auto Layout cannot squeeze the capsule below waveform + status column
        // + padding + gaps, so the compact width is exactly that floor: asking
        // for less would just be clamped and the text row would still show.
        XCTAssertEqual(OverlayMetrics.sessionCompactWidth, OverlayMetrics.sessionLayoutMinimumWidth)
        XCTAssertGreaterThanOrEqual(OverlayMetrics.sessionLayoutMinimumWidth,
                                    OverlayMetrics.horizontalPadding * 2
                                        + OverlayMetrics.waveformSlot
                                        + OverlayMetrics.sessionTrailingWidth)
        XCTAssertGreaterThan(OverlayMetrics.sessionWidth(for: "一些正在说的字"),
                             OverlayMetrics.sessionCompactWidth)
    }

    func testLayoutConstantsStillAddUpToTheOriginalPadding() {
        // The measured capsule sizes must not drift when the constants are
        // re-expressed as arithmetic.
        XCTAssertEqual(OverlayMetrics.internalPadding, 162)
        XCTAssertEqual(OverlayMetrics.sessionInternalPadding,
                       OverlayMetrics.internalPadding + OverlayMetrics.sessionTrailingExtra)
    }

    func testSessionWidthAccountsForTheWiderStatusColumn() {
        let text = "hello world"
        let focused = OverlayMetrics.capsuleWidth(for: text)
        let session = OverlayMetrics.sessionWidth(for: text)
        XCTAssertEqual(session - focused, OverlayMetrics.sessionTrailingExtra, accuracy: 0.01,
                       "the text area must shrink by exactly the wider trailing column")
    }

    func testSessionWidthIsMonotonicAndClamped() {
        var last: CGFloat = 0
        for count in 1...200 {
            let width = OverlayMetrics.sessionWidth(for: String(repeating: "a", count: count))
            XCTAssertGreaterThanOrEqual(width, last)
            XCTAssertLessThanOrEqual(width, OverlayMetrics.maxWidth)
            last = width
        }
        XCTAssertEqual(OverlayMetrics.sessionWidth(for: String(repeating: "a", count: 5_000)),
                       OverlayMetrics.maxWidth)
    }

    func testEmptySessionTextStillClearsTheCompactPill() {
        XCTAssertGreaterThanOrEqual(OverlayMetrics.sessionWidth(for: ""),
                                    OverlayMetrics.sessionCompactWidth)
    }

    func testSessionDurationLabelIsAlwaysMinutesAndSeconds() {
        XCTAssertEqual(OverlayMetrics.sessionDurationLabel(seconds: 0), "0:00")
        XCTAssertEqual(OverlayMetrics.sessionDurationLabel(seconds: 9), "0:09")
        XCTAssertEqual(OverlayMetrics.sessionDurationLabel(seconds: 102), "1:42")
        XCTAssertEqual(OverlayMetrics.sessionDurationLabel(seconds: -3), "0:00")
    }
}
