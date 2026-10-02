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
    /// Capsule padding and slot sizes. Every width in this file is derived from
    /// these, so the view and the math can never disagree.
    static let horizontalPadding: CGFloat = 24
    static let waveformSlot: CGFloat = 44
    static let stackGap: CGFloat = 14
    static let timerSlot: CGFloat = 42
    /// Fixed non-text space inside the capsule: horizontal padding + waveform
    /// + timer + gaps.
    static let internalPadding: CGFloat =
        horizontalPadding * 2 + waveformSlot + timerSlot + stackGap * 2

    // MARK: - Continuous dictation (session) layout

    /// A relay session keeps the capsule on screen for minutes, so it is a
    /// fixed-height HUD: the text row never wraps, and the whole capsule
    /// collapses to a slim pill once the user stops talking.
    static let sessionHeight: CGFloat = 56
    static let sessionCompactHeight: CGFloat = 44
    /// Trailing column: elapsed clock on top, segment status underneath.
    static let sessionTrailingWidth: CGFloat = 92
    /// Hard floor of the session layout: the capsule can never be narrower than
    /// waveform + status column + padding + gaps, whatever the text does.
    static let sessionLayoutMinimumWidth: CGFloat =
        horizontalPadding * 2 + waveformSlot + sessionTrailingWidth + stackGap * 2
    /// The slim pill the persistent HUD collapses to: this floor, at a reduced
    /// height. The text row is squeezed out by the constraints themselves.
    static let sessionCompactWidth: CGFloat = sessionLayoutMinimumWidth
    /// The focused layout reserves `timerSlot` at the trailing edge; the
    /// session column is wider, so the text area shrinks by this much.
    static let sessionTrailingExtra: CGFloat = sessionTrailingWidth - timerSlot
    static let sessionInternalPadding: CGFloat = internalPadding + sessionTrailingExtra

    /// Elapsed silence after which the session capsule shrinks out of the way.
    /// Tied to the rotation threshold so a pause that is *about* to become a
    /// segment does not also collapse the HUD.
    static func compactIdleThreshold(idleThreshold: TimeInterval) -> TimeInterval {
        max(idleThreshold * 2, 8)
    }

    /// Session capsule width for `text` (1 line, tail-truncated).
    /// `trailingExtra` is the width the status column steals from the text row;
    /// pass 0 when that column is hidden (the closing summary) so the text gets
    /// the room back instead of being truncated.
    static func sessionWidth(for text: String,
                             trailingExtra: CGFloat = sessionTrailingExtra) -> CGFloat {
        let width = estimatedTextWidth(for: text) + internalPadding + trailingExtra
        return min(max(width, sessionCompactWidth), maxWidth)
    }

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

    /// Capsules never look pill-shaped while tall, so the corner radius is
    /// clamped to this value instead of following height all the way down.
    static let maxCornerRadius: CGFloat = 28

    /// Corner radius for a capsule of `height`: a true pill while short, and
    /// clamped once the capsule grows tall enough for a full round to look
    /// bloated. (Freezing the radius at the single-line value made multi-line
    /// capsules read as plain rounded rectangles.)
    static func cornerRadius(forHeight height: CGFloat) -> CGFloat {
        min(max(height, 0) / 2, maxCornerRadius)
    }

    /// Session summary clock: always m:ss, unlike the live "9s" counter.
    static func sessionDurationLabel(seconds: Int) -> String {
        let clamped = max(seconds, 0)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    /// True when the character renders roughly one em wide (CJK / fullwidth /
    /// emoji), i.e. not a narrow latin glyph.
    static func isWide(_ character: Character) -> Bool {
        for scalar in character.unicodeScalars {
            switch scalar.value {
            case 0x1100...0x115F,    // hangul jamo
                 0x2000...0x206F,    // general punctuation: the “…” in every status line renders full-width
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

/// Pure indeterminate ("busy") bar animation for the overlay: a soft bump
/// sweeps out and back across the bars so a stage that is *not* listening to
/// the microphone still reads as alive. Deterministic given `phase`
/// (0...1, wraps), which makes it testable without a display refresh.
struct IndeterminateWaveform {
    let barCount: Int
    /// Bar height when the bump is somewhere else — never fully flat, so the
    /// capsule still looks alive between sweeps.
    let resting: Float
    let peak: Float
    /// Travel distance covered by the bump, in bars.
    let spread: Float

    init(barCount: Int = 5, resting: Float = 0.16, peak: Float = 0.92, spread: Float = 1.6) {
        self.barCount = barCount
        self.resting = resting
        self.peak = peak
        self.spread = spread
    }

    /// One bar fraction (0...1) per bar for a bump sweeping at `phase`.
    func bars(atPhase phase: Float) -> [Float] {
        guard barCount > 0 else { return [] }
        let progress = phase - phase.rounded(.down)
        // Ping-pong instead of wrap-around: the two outermost bars are the ends
        // of a linear chart, not neighbours, so wrapping would light them both
        // at the same time and read as a glitch.
        let travel = progress < 0.5 ? progress * 2 : (1 - progress) * 2
        let span = Float(max(barCount - 1, 1))
        let center = travel * span
        return (0..<barCount).map { index in
            let falloff = min(max(1 - abs(Float(index) - center) / spread, 0), 1)
            // Smoothstep so the bump eases in and out instead of snapping.
            let shaped = falloff * falloff * (3 - 2 * falloff)
            return min(max(resting + (peak - resting) * shaped, 0), 1)
        }
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