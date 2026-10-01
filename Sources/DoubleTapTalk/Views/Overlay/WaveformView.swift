import AppKit

/// Renders the five-bar waveform driven by `WaveformAnimator` bar fractions.
final class WaveformView: NSView {
    private var barFractions: [Float] = []
    private let barWidth: CGFloat = 5
    private let barSpacing: CGFloat = 3
    private let cornerRadius: CGFloat = 2.5

    override var isOpaque: Bool { false }
    override var wantsUpdateLayer: Bool { false }

    func setBars(_ fractions: [Float]) {
        barFractions = fractions
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard barFractions.count > 0 else { return }

        let totalWidth = CGFloat(barFractions.count) * barWidth
            + CGFloat(barFractions.count - 1) * barSpacing
        let startX = (bounds.width - totalWidth) / 2
        let maxHeight = bounds.height - 8

        for (index, fraction) in barFractions.enumerated() {
            let barHeight = max(4, maxHeight * CGFloat(fraction))
            let x = startX + CGFloat(index) * (barWidth + barSpacing)
            let y = (bounds.height - barHeight) / 2
            let rect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.white.withAlphaComponent(0.9).setFill()
            path.fill()
        }
    }
}