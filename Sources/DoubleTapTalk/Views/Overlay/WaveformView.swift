import AppKit

/// Renders the capsule's leading activity slot at a fixed width: either bars
/// driven by `WaveformAnimator` / `IndeterminateWaveform`, or a single state
/// symbol. Keeping the slot width constant means the capsule never reflows when
/// the overlay switches state.
final class WaveformView: NSView {
    enum Mode: Equatable {
        case bars([Float])
        case symbol(String)
    }

    private var mode: Mode = .bars([])
    private var tint: NSColor = NSColor.white.withAlphaComponent(0.9)

    private let barWidth: CGFloat = 5
    private let barSpacing: CGFloat = 3
    private let cornerRadius: CGFloat = 2.5

    override var isOpaque: Bool { false }
    override var wantsUpdateLayer: Bool { false }

    func setBars(_ fractions: [Float]) {
        mode = .bars(fractions)
        needsDisplay = true
    }

    func setSymbol(_ name: String) {
        mode = .symbol(name)
        needsDisplay = true
    }

    func setTint(_ color: NSColor) {
        tint = color
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        switch mode {
        case .bars(let fractions):
            drawBars(fractions)
        case .symbol(let name):
            drawSymbol(named: name)
        }
    }

    private func drawBars(_ fractions: [Float]) {
        guard fractions.count > 0 else { return }

        let totalWidth = CGFloat(fractions.count) * barWidth
            + CGFloat(fractions.count - 1) * barSpacing
        let startX = (bounds.width - totalWidth) / 2
        let maxHeight = bounds.height - 8

        tint.setFill()
        for (index, fraction) in fractions.enumerated() {
            let barHeight = max(4, maxHeight * CGFloat(fraction))
            let x = startX + CGFloat(index) * (barWidth + barSpacing)
            let y = (bounds.height - barHeight) / 2
            let rect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            path.fill()
        }
    }

    /// Draws a tinted SF Symbol, centered in the slot. The size is fixed so the
    /// glyph does not pulse as the name changes between states.
    private func drawSymbol(named name: String) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let tinted = base.withSymbolConfiguration(
            NSImage.SymbolConfiguration(paletteColors: [tint])
        ) ?? base
        let size = tinted.size
        tinted.draw(in: NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        ))
    }
}
