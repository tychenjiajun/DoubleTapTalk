import XCTest
@testable import DoubleTapTalk

/// Tests for the waveform envelope + jitter animation math (pure, deterministic).
final class WaveformAnimatorTests: XCTestCase {

    private let weights: [Float] = [0.5, 0.8, 1.0, 0.75, 0.55]

    func testProducesFiveBars() {
        var animator = WaveformAnimator(weights: weights)
        let bars = animator.update(targetLevel: 0.8, random: 0.5)
        XCTAssertEqual(bars.count, 5)
    }

    func testRisingUsesAttackCoefficient() {
        // Attack = 40%: from 0 to 1.0 in one step → 0.4.
        var animator = WaveformAnimator(weights: weights)
        let bars = animator.update(targetLevel: 1.0, random: 0.5)
        // No jitter at random 0.5 → bar = 0.4 * weight
        XCTAssertEqual(bars[0], 0.4 * 0.5, accuracy: 0.0001)
        XCTAssertEqual(bars[2], 0.4 * 1.0, accuracy: 0.0001)
    }

    func testFallingUsesReleaseCoefficient() {
        // Release = 15%: starting at 1.0, target 0 → 0.85.
        var animator = WaveformAnimator(weights: weights, initialLevel: 1.0)
        let bars = animator.update(targetLevel: 0.0, random: 0.5)
        XCTAssertEqual(bars[2], 0.85 * 1.0, accuracy: 0.0001)
    }

    func testBarsGrowMonotonicallyWhileRising() {
        var animator = WaveformAnimator(weights: weights)
        var previous = animator.update(targetLevel: 0.9, random: 0.5)
        for _ in 0..<10 {
            let bars = animator.update(targetLevel: 0.9, random: 0.5)
            for i in 0..<bars.count {
                XCTAssertGreaterThanOrEqual(bars[i], previous[i], "Bar \(i) must not shrink while level is high")
            }
            previous = bars
        }
    }

    func testJitterScalesBarWithinFourPercent() {
        var animator = WaveformAnimator(weights: weights, initialLevel: 1.0)
        // random 0 → -4% jitter; random 1 → +4% jitter.
        let low = animator.update(targetLevel: 1.0, random: 0.0)
        let high = animator.update(targetLevel: 1.0, random: 1.0)
        // Weights 0.5 and 0.8 stay below the 1.0 clamp even at +4%.
        XCTAssertEqual(low[0], 0.5 * 0.96, accuracy: 0.0001)
        XCTAssertEqual(high[0], 0.5 * 1.04, accuracy: 0.0001)
        XCTAssertEqual(low[1], 0.8 * 0.96, accuracy: 0.0001)
        XCTAssertEqual(high[1], 0.8 * 1.04, accuracy: 0.0001)
        // The center bar (weight 1.0) must still clamp to full scale.
        XCTAssertEqual(high[2], 1.0, accuracy: 0.0001)
    }

    func testJitterAlwaysWithinBounds() {
        var animator = WaveformAnimator(weights: weights)
        for _ in 0..<50 {
            let random = Float.random(in: 0...1)
            let level = Float.random(in: 0...1)
            let bars = animator.update(targetLevel: level, random: random)
            for bar in bars {
                XCTAssertTrue(bar >= 0 && bar <= 1.0, "Bar fraction must stay in [0,1], got \(bar)")
            }
        }
    }

    func testCenterBarIsTallest() {
        var animator = WaveformAnimator(weights: weights, initialLevel: 1.0)
        let bars = animator.update(targetLevel: 1.0, random: 0.5)
        XCTAssertEqual(bars[2], 1.0, accuracy: 0.0001, "Center bar should reach full height")
        XCTAssertLessThan(bars[0], bars[1])
        XCTAssertLessThan(bars[1], bars[2])
        XCTAssertGreaterThan(bars[2], bars[3])
        XCTAssertGreaterThan(bars[3], bars[4])
    }

    func testQuietInputProducesQuietBars() {
        var animator = WaveformAnimator(weights: weights)
        let bars = animator.update(targetLevel: 0.05, random: 0.5)
        for bar in bars {
            XCTAssertLessThan(bar, 0.03, "Quiet level should produce near-zero bars (attack applied)")
        }
        XCTAssertEqual(bars[2], 0.05 * 0.4, accuracy: 0.0001)
    }
}

/// Tests for the overlay capsule sizing + audio level normalization math.
final class OverlayMetricsTests: XCTestCase {

    // MARK: - Capsule width

    func testEmptyTextUsesMinWidth() {
        let width = OverlayMetrics.capsuleWidth(for: "")
        XCTAssertEqual(width, OverlayMetrics.minWidth)
    }

    func testShortTextClampsToMinWidth() {
        let width = OverlayMetrics.capsuleWidth(for: "hi")
        XCTAssertEqual(width, OverlayMetrics.minWidth)
    }

    func testWidthGrowsWithTextLength() {
        let short = OverlayMetrics.capsuleWidth(for: String(repeating: "a", count: 20))
        let long = OverlayMetrics.capsuleWidth(for: String(repeating: "a", count: 40))
        XCTAssertGreaterThan(long, short, "Longer text must produce a wider capsule")
    }

    func testLongTextClampsToMaxWidth() {
        let width = OverlayMetrics.capsuleWidth(for: String(repeating: "a", count: 2000))
        XCTAssertEqual(width, OverlayMetrics.maxWidth)
    }

    func testWidthIsMonotonic() {
        var last: CGFloat = 0
        for count in 1...100 {
            let width = OverlayMetrics.capsuleWidth(for: String(repeating: "a", count: count))
            XCTAssertGreaterThanOrEqual(width, last, "Width must never shrink as text grows")
            last = width
        }
    }

    // MARK: - Capsule height (long sentences wrap and grow the capsule)

    func testShortTextKeepsBaseHeight() {
        XCTAssertEqual(OverlayMetrics.capsuleHeight(for: ""), OverlayMetrics.baseHeight)
        XCTAssertEqual(OverlayMetrics.capsuleHeight(for: "Listening…"), OverlayMetrics.baseHeight)
        XCTAssertEqual(OverlayMetrics.capsuleHeight(for: String(repeating: "a", count: 20)), OverlayMetrics.baseHeight)
    }

    func testLongTextGrowsCapsuleHeight() {
        let medium = OverlayMetrics.capsuleHeight(for: String(repeating: "a", count: 60))
        let long = OverlayMetrics.capsuleHeight(for: String(repeating: "a", count: 120))
        XCTAssertGreaterThan(medium, OverlayMetrics.baseHeight, "a long sentence must wrap, not truncate")
        XCTAssertGreaterThan(long, medium, "more text must mean a taller capsule")
    }

    func testHeightIsCappedAtMaxLines() {
        let huge = OverlayMetrics.capsuleHeight(for: String(repeating: "a", count: 5000))
        XCTAssertEqual(huge, OverlayMetrics.baseHeight + CGFloat(OverlayMetrics.maxLines - 1) * OverlayMetrics.lineHeight)
        XCTAssertEqual(OverlayMetrics.lineCount(for: String(repeating: "a", count: 5000),
                                                width: OverlayMetrics.maxWidth), OverlayMetrics.maxLines)
    }

    func testLineCountIsMonotonicAndAtLeastOne() {
        XCTAssertEqual(OverlayMetrics.lineCount(for: "", width: OverlayMetrics.maxWidth), 1)
        var last = 1
        for count in 1...400 {
            let lines = OverlayMetrics.lineCount(for: String(repeating: "你", count: count),
                                                 width: OverlayMetrics.maxWidth)
            XCTAssertGreaterThanOrEqual(lines, last, "line count must never shrink as text grows")
            XCTAssertLessThanOrEqual(lines, OverlayMetrics.maxLines)
            last = lines
        }
    }

    // MARK: - Elapsed seconds label

    func testElapsedLabelUnderOneMinuteShowsSeconds() {
        XCTAssertEqual(OverlayMetrics.elapsedLabel(seconds: 0), "0s")
        XCTAssertEqual(OverlayMetrics.elapsedLabel(seconds: 1), "1s")
        XCTAssertEqual(OverlayMetrics.elapsedLabel(seconds: 59), "59s")
    }

    func testElapsedLabelOverOneMinuteShowsMinutes() {
        XCTAssertEqual(OverlayMetrics.elapsedLabel(seconds: 60), "1:00")
        XCTAssertEqual(OverlayMetrics.elapsedLabel(seconds: 61), "1:01")
        XCTAssertEqual(OverlayMetrics.elapsedLabel(seconds: 125), "2:05")
        XCTAssertEqual(OverlayMetrics.elapsedLabel(seconds: 3661), "61:01")
    }

    func testElapsedLabelClampsNegative() {
        XCTAssertEqual(OverlayMetrics.elapsedLabel(seconds: -5), "0s")
    }
}