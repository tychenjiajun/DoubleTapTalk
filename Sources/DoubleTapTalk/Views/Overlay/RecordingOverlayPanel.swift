import AppKit
import QuartzCore

/// Frameless capsule overlay shown while recording: vibrance capsule with a
/// five-bar waveform, live transcription label, elastic width and spring
/// animations. Feed it audio levels + text; it handles all animation.
final class RecordingOverlayPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let timerLabel = NSTextField(labelWithString: "0s")
    private let waveformView = WaveformView()
    private weak var capsuleView: NSVisualEffectView?
    private var animator = WaveformAnimator()
    private var displayTimer: Timer?

    private let capsuleHeight: CGFloat = OverlayMetrics.baseHeight
    private let hPadding: CGFloat = 24
    private let waveSize: CGFloat = 44
    private let stackGap: CGFloat = 14
    private let timerWidth: CGFloat = 42
    private var isShowing = false

    /// Elapsed-seconds clock shown at the trailing edge of the capsule.
    private var startedAt: Date?
    private var elapsedSeconds = 0
    private var isTimerRunning = false

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
        startRecordingTimer()

        let width = OverlayMetrics.capsuleWidth(for: text)
        layoutLabel(for: width)
        let height = measuredHeight(for: text, width: width)
        let frame = centeredFrame(width: width, height: height)
        setFrame(NSRect(x: frame.minX, y: frame.minY - 14, width: width, height: height), display: false)
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

        // Elastic width/height transition: a long sentence wraps and the
        // capsule grows vertically instead of truncating.
        let width = OverlayMetrics.capsuleWidth(for: text)
        layoutLabel(for: width)
        let height = measuredHeight(for: text, width: width)
        let frame = centeredFrame(width: width, height: height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(frame, display: true)
        }
    }

    /// Freezes the seconds counter (recording ended; the capsule may still be
    /// showing "transcribing…").
    func stopRecordingTimer() {
        guard isTimerRunning else { return }
        isTimerRunning = false
        refreshTimerLabel()
    }

    /// Raw audio level in 0...1 — smoothed by the animator at display rate.
    func setAudioLevel(_ level: Float) {
        guard isShowing, displayTimer != nil else { return }
        pendingLevel = level
    }

    func dismiss() {
        guard isShowing else { return }
        isShowing = false
        isTimerRunning = false
        startedAt = nil
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
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = OverlayMetrics.maxLines
        label.usesSingleLineMode = false
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(label)

        // Elapsed seconds (kept at the trailing edge, fixed width so the
        // capsule doesn't jitter as digits change).
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timerLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        timerLabel.alignment = .right
        timerLabel.setContentHuggingPriority(.required, for: .horizontal)
        timerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        stack.addArrangedSubview(timerLabel)

        NSLayoutConstraint.activate([
            waveformView.widthAnchor.constraint(equalToConstant: waveSize),
            waveformView.heightAnchor.constraint(equalToConstant: 32),
            timerLabel.widthAnchor.constraint(equalToConstant: timerWidth),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: hPadding),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -hPadding),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
        ])
    }

    /// Gives the multi-line label a wrap width that matches the capsule's
    /// text area (AppKit needs this to compute a wrapped intrinsic height).
    private func layoutLabel(for width: CGFloat) {
        label.preferredMaxLayoutWidth = max(width - OverlayMetrics.internalPadding, 40)
    }

    /// Capsule height from the label's *real* wrapped size (AppKit-accurate),
    /// clamped to `maxLines`; falls back to the pure estimate if AppKit reports
    /// nothing usable yet.
    private func measuredHeight(for text: String, width: CGFloat) -> CGFloat {
        let measured = label.intrinsicContentSize.height
        guard measured > 0 else {
            return OverlayMetrics.height(forLines: OverlayMetrics.lineCount(for: text, width: width))
        }
        let lines = Int((measured / OverlayMetrics.lineHeight).rounded())
        return OverlayMetrics.height(forLines: lines)
    }

    private func centeredFrame(width: CGFloat, height: CGFloat) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 100, width: width, height: height)
        }
        let visible = screen.visibleFrame
        let x = visible.midX - width / 2
        let y = visible.minY + 56
        return NSRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Seconds counter

    private func startRecordingTimer() {
        startedAt = Date()
        elapsedSeconds = 0
        isTimerRunning = true
        timerLabel.stringValue = OverlayMetrics.elapsedLabel(seconds: 0)
    }

    private func refreshTimerLabel() {
        guard let startedAt else { return }
        let seconds = isTimerRunning ? Int(Date().timeIntervalSince(startedAt)) : elapsedSeconds
        elapsedSeconds = seconds
        let text = OverlayMetrics.elapsedLabel(seconds: seconds)
        if timerLabel.stringValue != text {
            timerLabel.stringValue = text
        }
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
        refreshTimerLabel()

        let level = pendingLevel
        pendingLevel = 0
        let random = Float.random(in: 0...1)
        let bars = animator.update(targetLevel: level, random: random)
        waveformView.setBars(bars)
    }
}