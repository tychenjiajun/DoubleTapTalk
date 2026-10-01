import AppKit
import QuartzCore

/// Frameless capsule overlay shown while recording: vibrance capsule with a
/// five-bar waveform, live transcription label, elastic width and spring
/// animations. Feed it audio levels + text; it handles all animation.
final class RecordingOverlayPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let waveformView = WaveformView()
    private weak var capsuleView: NSVisualEffectView?
    private var animator = WaveformAnimator()
    private var displayTimer: Timer?

    private let capsuleHeight: CGFloat = 56
    private let hPadding: CGFloat = 24
    private let waveSize: CGFloat = 44
    private let stackGap: CGFloat = 14
    private var isShowing = false

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: OverlayMetrics.minWidth, height: capsuleHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setupCapsule()
    }

    // MARK: - Public API

    func show(text: String = "Listening…") {
        isShowing = true
        label.stringValue = text

        let width = OverlayMetrics.capsuleWidth(for: text)
        let frame = centeredFrame(width: width)
        setFrame(NSRect(x: frame.minX, y: frame.minY - 14, width: width, height: capsuleHeight), display: false)
        alphaValue = 0
        orderFrontRegardless()
        startDisplayTimer()

        // Spring entry animation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.1)
            animator().alphaValue = 1
            animator().setFrame(frame, display: true)
        }
    }

    func updateText(_ text: String) {
        guard isShowing else { return }
        label.stringValue = text

        // Elastic width transition
        let width = OverlayMetrics.capsuleWidth(for: text)
        let frame = centeredFrame(width: width)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(frame, display: true)
        }
    }

    /// Raw audio level in 0...1 — smoothed by the animator at display rate.
    func setAudioLevel(_ level: Float) {
        guard isShowing, displayTimer != nil else { return }
        pendingLevel = level
    }

    func dismiss() {
        guard isShowing else { return }
        isShowing = false
        stopDisplayTimer()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
        }

        // Scale-down exit on the capsule layer
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 0.9
        scale.duration = 0.22
        scale.timingFunction = CAMediaTimingFunction(name: .easeIn)
        capsuleView?.layer?.add(scale, forKey: "exitScale")
        capsuleView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.9, y: 0.9))
    }

    // MARK: - Internals

    private var pendingLevel: Float = 0

    private func setupCapsule() {
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        guard let contentView = contentView else { return }
        contentView.wantsLayer = true

        // Shadow host behind the vibrancy capsule
        let shadowHost = NSView(frame: contentView.bounds)
        shadowHost.autoresizingMask = [.width, .height]
        shadowHost.wantsLayer = true
        shadowHost.layer?.shadowColor = NSColor.black.withAlphaComponent(0.45).cgColor
        shadowHost.layer?.shadowOffset = CGSize(width: 0, height: -2)
        shadowHost.layer?.shadowRadius = 16
        shadowHost.layer?.shadowOpacity = 1
        contentView.addSubview(shadowHost)

        // Vibrancy capsule
        let effect = NSVisualEffectView(frame: contentView.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = capsuleHeight / 2
        effect.layer?.masksToBounds = true
        effect.appearance = NSAppearance(named: .darkAqua)
        capsuleView = effect
        shadowHost.addSubview(effect)

        // Subtle inner border for depth
        let border = NSView(frame: contentView.bounds)
        border.autoresizingMask = [.width, .height]
        border.wantsLayer = true
        border.layer?.cornerRadius = capsuleHeight / 2
        border.layer?.borderWidth = 0.5
        border.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        effect.addSubview(border)

        // Layout: waveform + label
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = stackGap
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(waveformView)

        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.92)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(label)

        NSLayoutConstraint.activate([
            waveformView.widthAnchor.constraint(equalToConstant: waveSize),
            waveformView.heightAnchor.constraint(equalToConstant: 32),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: hPadding),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -hPadding),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
        ])
    }

    private func centeredFrame(width: CGFloat) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 100, width: width, height: capsuleHeight)
        }
        let visible = screen.visibleFrame
        let x = visible.midX - width / 2
        let y = visible.minY + 56
        return NSRect(x: x, y: y, width: width, height: capsuleHeight)
    }

    private func startDisplayTimer() {
        stopDisplayTimer()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func tick() {
        let level = pendingLevel
        pendingLevel = 0
        let random = Float.random(in: 0...1)
        let bars = animator.update(targetLevel: level, random: random)
        waveformView.setBars(bars)
    }
}