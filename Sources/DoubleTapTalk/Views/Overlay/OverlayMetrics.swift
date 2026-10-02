import Foundation
import CoreGraphics

/// Pure sizing/normalization math for the recording overlay capsule (testable).
struct OverlayMetrics {
    /// Label font size — glyph widths are estimated in ems below.
    static let fontSize: CGFloat = 15
    static let minWidth: CGFloat = 200
    /// Capsule grows horizontally up to this before it starts wrapping.
    static let maxWidth: CGFloat = 620
    /// Capsule height for a single-line label.
    static let baseHeight: CGFloat = 56
    /// Long text wraps instead of truncating — the capsule grows vertically.
    static let maxLines = 4
    static let lineHeight: CGFloat = 20
    /// Fixed non-text space inside the capsule: horizontal padding + waveform
    /// + timer + gaps.
    static let internalPadding: CGFloat = 162

    /// Estimated rendered width of `text`. Ideographic glyphs (CJK, kana,
    /// hangul, fullwidth forms, emoji) occupy ~1 em; word-script glyphs ~0.52 em
    /// at SF 15 pt. This is what keeps "先横向生长" honest: a short Chinese
    /// sentence must not wrap just because 8.5 pt/char underestimated it.
    static func estimatedTextWidth(for text: String) -> CGFloat {
        text.reduce(0) { total, character in
            total + (isWide(character) ? fontSize : fontSize * 0.52)
        }
    }

    /// Elastic capsule width: grows with text, clamped between min and max.
    static func capsuleWidth(for text: String) -> CGFloat {
        let textWidth = estimatedTextWidth(for: text) + internalPadding
        return min(max(textWidth, minWidth), maxWidth)
    }

    /// How many visual lines the label needs at `width` (1...maxLines).
    /// Stays at 1 line until the capsule is clamped at `maxWidth`, so text is
    /// laid out horizontally first and only wraps once there is no more room.
    static func lineCount(for text: String, width: CGFloat) -> Int {
        let usable = max(width - internalPadding, fontSize)
        let needed = max(estimatedTextWidth(for: text) - 1, 0)   // 1 pt slack
        guard needed > 0 else { return 1 }
        let lines = Int((needed / usable).rounded(.up))
        return min(max(lines, 1), maxLines)
    }

    /// Capsule height for a given number of (clamped) lines.
    static func height(forLines lines: Int) -> CGFloat {
        let clamped = min(max(lines, 1), maxLines)
        return baseHeight + CGFloat(clamped - 1) * lineHeight
    }

    /// Capsule height for `text`: grows one line at a time so a long sentence is
    /// readable instead of being truncated to a single line.
    static func capsuleHeight(for text: String) -> CGFloat {
        height(forLines: lineCount(for: text, width: capsuleWidth(for: text)))
    }

    /// Recording clock: "0s", "59s", then "1:00", "12:05".
    static func elapsedLabel(seconds: Int) -> String {
        let clamped = max(seconds, 0)
        if clamped < 60 { return "\(clamped)s" }
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    /// True when the character renders roughly one em wide (CJK / fullwidth /
    /// emoji), i.e. not a narrow latin glyph.
    static func isWide(_ character: Character) -> Bool {
        for scalar in character.unicodeScalars {
            switch scalar.value {
            case 0x1100...0x115F,    // hangul jamo
                 0x2E80...0x303E,    // CJK radicals + symbols/punctuation
                 0x3041...0x33FF,    // kana, CJK compatibility
                 0x3400...0x4DBF,    // CJK ext A
                 0x4E00...0x9FFF,    // CJK unified ideographs
                 0xA000...0xA4CF,    // yi
                 0xAC00...0xD7A3,    // hangul syllables
                 0xF900...0xFAFF,    // CJK compatibility ideographs
                 0xFE30...0xFE6F,    // CJK compatibility forms
                 0xFF00...0xFF60,    // fullwidth forms
                 0xFFE0...0xFFE6,    // fullwidth signs
                 0x1F300...0x1FAFF,  // emoji / symbols
                 0x20000...0x2FA1F:  // CJK ext B+
                return true
            default:
                continue
            }
        }
        return false
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