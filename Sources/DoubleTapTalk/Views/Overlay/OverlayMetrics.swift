import Foundation
import CoreGraphics

/// Pure sizing/normalization math for the recording overlay capsule (testable).
struct OverlayMetrics {
    static let minWidth: CGFloat = 200
    static let maxWidth: CGFloat = 560
    /// Capsule height for a single-line label.
    static let baseHeight: CGFloat = 56
    /// Long text wraps instead of truncating — the capsule grows vertically.
    static let maxLines = 4
    static let lineHeight: CGFloat = 20
    /// Estimated width of a single average character at the label's font size.
    static let avgCharWidth: CGFloat = 8.5
    /// Fixed non-text space inside the capsule: horizontal padding + waveform
    /// + timer + gaps.
    static let internalPadding: CGFloat = 162

    /// Elastic capsule width: grows with text, clamped between min and max.
    static func capsuleWidth(for text: String) -> CGFloat {
        let textWidth = CGFloat(text.count) * avgCharWidth + internalPadding
        return min(max(textWidth, minWidth), maxWidth)
    }

    /// How many visual lines the label needs at `width` (1...maxLines).
    static func lineCount(for text: String, width: CGFloat) -> Int {
        let usable = max(width - internalPadding, avgCharWidth)
        let charsPerLine = max(Int(usable / avgCharWidth), 1)
        guard !text.isEmpty else { return 1 }
        let lines = Int((Double(text.count) / Double(charsPerLine)).rounded(.up))
        return min(max(lines, 1), maxLines)
    }

    /// Capsule height for `text`: grows one line at a time so a long sentence is
    /// readable instead of being truncated to a single line.
    static func capsuleHeight(for text: String) -> CGFloat {
        let lines = lineCount(for: text, width: capsuleWidth(for: text))
        return baseHeight + CGFloat(lines - 1) * lineHeight
    }

    /// Recording clock: "0s", "59s", then "1:00", "12:05".
    static func elapsedLabel(seconds: Int) -> String {
        let clamped = max(seconds, 0)
        if clamped < 60 { return "\(clamped)s" }
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
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