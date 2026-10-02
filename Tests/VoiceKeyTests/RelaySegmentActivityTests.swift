import XCTest
@testable import DoubleTapTalk

/// Pure idle-detection logic for the continuous (relay) dictation segments:
/// a segment rotates only after `threshold` seconds with NO *new* words, and
/// only once it has actually heard speech.
final class RelaySegmentActivityTests: XCTestCase {

    func testSilentSegmentNeverRotates() {
        let activity = RelaySegmentActivity()
        XCTAssertFalse(activity.hasHeardText)
        // Even far in the future, a segment that never heard text must not rotate.
        XCTAssertFalse(activity.shouldRotate(now: Date().addingTimeInterval(60), threshold: 3))
    }

    func testEmptyTextDoesNotCountAsSpeech() {
        var activity = RelaySegmentActivity()
        XCTAssertFalse(activity.observe(text: ""))
        XCTAssertFalse(activity.hasHeardText)
        XCTAssertFalse(activity.shouldRotate(now: Date().addingTimeInterval(60), threshold: 3))
    }

    func testIdenticalPartialRepeatsNeverResetIdleDeadline() {
        var activity = RelaySegmentActivity()
        _ = activity.observe(text: "hello")   // t0
        XCTAssertTrue(activity.hasHeardText)
        // The recognizer re-emits the same best text constantly while streaming:
        // none of these may reset the deadline.
        XCTAssertFalse(activity.observe(text: "hello"))
        XCTAssertFalse(activity.observe(text: "hello"))
        // ~3.5s after the only real change → rotation due.
        XCTAssertTrue(activity.shouldRotate(now: Date().addingTimeInterval(3.5), threshold: 3))
    }

    func testNewWordResetsIdleDeadline() {
        var activity = RelaySegmentActivity()
        _ = activity.observe(text: "hello")   // t0
        _ = activity.observe(text: "hello wor")  // t1 ≈ t0 + ε
        _ = activity.observe(text: "hello world") // t2 ≈ t0 + 2ε

        // Immediately after the newest word: no rotation (< threshold).
        XCTAssertFalse(activity.shouldRotate(now: Date().addingTimeInterval(2.0), threshold: 3))
        // After the threshold has passed since the newest word: rotate.
        XCTAssertTrue(activity.shouldRotate(now: Date().addingTimeInterval(3.5), threshold: 3))
    }

    func testFinalSettleWithShortPauseThenMoreSpeech() {
        var activity = RelaySegmentActivity()
        _ = activity.observe(text: "苹果")
        // User pauses (2s < 3s threshold), then speaks again.
        _ = activity.observe(text: "苹果识别")
        XCTAssertFalse(activity.shouldRotate(now: Date().addingTimeInterval(2.0), threshold: 3))
        // Then a long pause.
        XCTAssertTrue(activity.shouldRotate(now: Date().addingTimeInterval(4.0), threshold: 3))
    }

    func testRespectsCustomThreshold() {
        var activity = RelaySegmentActivity()
        _ = activity.observe(text: "a")
        XCTAssertFalse(activity.shouldRotate(now: Date().addingTimeInterval(2.0), threshold: 2.5))
        XCTAssertTrue(activity.shouldRotate(now: Date().addingTimeInterval(3.0), threshold: 2.5))
    }

    func testObserveReturnsTrueOnlyForNewText() {
        var activity = RelaySegmentActivity()
        XCTAssertTrue(activity.observe(text: "a"))
        XCTAssertFalse(activity.observe(text: "a"))
        XCTAssertTrue(activity.observe(text: "ab"))
        XCTAssertFalse(activity.observe(text: "ab"))
    }
}

/// The rotation finalize gate: when a segment rotates, Apple answers our own
/// `finish()`/`endAudio()` with a cancellation error (kAFAssistantErrorDomain
/// 209) instead of a final result. These tests pin that this callback ends the
/// bounded wait immediately — that bug added ~1.5s to EVERY rotated segment,
/// turning a configured 2s pause into ~4s of perceived latency.
final class RelaySegmentCloseGateTests: XCTestCase {

    func testWaitNeverEndsBeforeClosing() {
        var gate = RelaySegmentCloseGate()
        XCTAssertFalse(gate.isClosing)
        // Streaming partials before we cancel must not settle anything.
        gate.handleCallback(hasFinalResult: false, failed: false)
        XCTAssertFalse(gate.canEndWait)
    }

    func testOurCancellationEndsTheWaitImmediately() {
        var gate = RelaySegmentCloseGate()
        gate.beginClosing()
        XCTAssertTrue(gate.isClosing)
        // Error callback (209/203) instead of a final result — the common case.
        gate.handleCallback(hasFinalResult: false, failed: true)
        XCTAssertTrue(gate.canEndWait, "Our own cancellation must end the finalize wait, not burn the timeout")
    }

    func testFinalResultAfterClosingEndsTheWait() {
        var gate = RelaySegmentCloseGate()
        gate.beginClosing()
        gate.handleCallback(hasFinalResult: true, failed: false)
        XCTAssertTrue(gate.canEndWait)
    }

    func testSpontaneousFailureBeforeClosingDoesNotSettle() {
        var gate = RelaySegmentCloseGate()
        // A real recognition error while still streaming must NOT be mistaken
        // for our own cancellation — the session stays open.
        gate.handleCallback(hasFinalResult: false, failed: true)
        XCTAssertFalse(gate.canEndWait, "Only a close we initiated may end the wait")
        XCTAssertFalse(gate.isClosing)
    }

    func testSettlesOnceAndStaysSettled() {
        var gate = RelaySegmentCloseGate()
        gate.beginClosing()
        gate.handleCallback(hasFinalResult: false, failed: true)
        // Late callbacks after settling are ignored, never re-armed.
        gate.handleCallback(hasFinalResult: false, failed: false)
        XCTAssertTrue(gate.canEndWait)
    }

    func testPartialCallbackWhileClosingKeepsWaiting() {
        var gate = RelaySegmentCloseGate()
        gate.beginClosing()
        // A straggling partial can still improve the text — keep waiting.
        gate.handleCallback(hasFinalResult: false, failed: false)
        XCTAssertFalse(gate.canEndWait)
        gate.handleCallback(hasFinalResult: false, failed: true)
        XCTAssertTrue(gate.canEndWait)
    }
}