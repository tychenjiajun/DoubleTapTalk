import Foundation
import CoreGraphics

/// Pure sizing/normalization math for the recording overlay capsule (testable).
struct OverlayMetrics {
    static let minWidth: CGFloat = 160
    static let maxWidth: CGFloat = 560
    /// Estimated width of a single average character at the label's font size.
    static let avgCharWidth: CGFloat = 8.5
    /// Fixed non-text space inside the capsule: waveform + gaps + horizontal padding.
    static let internalPadding: CGFloat = 64

    /// Elastic capsule width: grows with text, clamped between min and max.
    static func capsuleWidth(for text: String) -> CGFloat {
        let textWidth = CGFloat(text.count) * avgCharWidth + internalPadding
        return min(max(textWidth, minWidth), maxWidth)
    }
}

/// Pure waveform animation state — envelope smoothing (attack/release) plus
/// per-bar jitter. The overlay view feeds raw RMS levels in and renders bar
/// fractions out. Deterministic given a supplied `random` value (testable).
struct WaveformAnimator {
    let weights: [Float]
    let attack: Float   // coefficient applied while the level is rising (e.g. 0.4)
    let release: Float  // coefficient applied while the level is falling (e.g. 0.15)
    let jitter: Float   // maximum relative per-bar jitter (e.g. 0.04)

    private(set) var smoothedLevel: Float

    init(
        weights: [Float] = [0.5, 0.8, 1.0, 0.75, 0.55],
        attack: Float = 0.4,
        release: Float = 0.15,
        jitter: Float = 0.04,
        initialLevel: Float = 0
    ) {
        self.weights = weights
        self.attack = attack
        self.release = release
        self.jitter = jitter
        self.smoothedLevel = initialLevel
    }

    /// Advances one animation frame.
    /// - Parameters:
    ///   - targetLevel: raw input level, 0...1 (RMS or normalized dB).
    ///   - random: 0...1 driving per-bar jitter (caller supplies randomness).
    /// - Returns: one bar fraction (0...1) per weight.
    mutating func update(targetLevel: Float, random: Float) -> [Float] {
        let target = min(max(targetLevel, 0), 1)
        let coefficient = target >= smoothedLevel ? attack : release
        smoothedLevel += (target - smoothedLevel) * coefficient

        let jitterOffset = (random - 0.5) * 2 * jitter
        return weights.map { weight in
            let fraction = smoothedLevel * weight * (1 + jitterOffset)
            return min(max(fraction, 0), 1)
        }
    }
}