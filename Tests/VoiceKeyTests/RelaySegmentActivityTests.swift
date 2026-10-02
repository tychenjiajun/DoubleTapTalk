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