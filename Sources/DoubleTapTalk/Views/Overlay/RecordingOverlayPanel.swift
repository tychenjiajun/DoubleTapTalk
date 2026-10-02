import AppKit
import QuartzCore

/// Frameless capsule overlay shown while recording: vibrance capsule with an
/// activity slot (live bars / travelling bump / state symbol), live
/// transcription label, elastic width and spring animations. Feed it state +
/// audio levels + text; it handles all animation.
///
/// Every stage of the pipeline has a distinct visual language (see
/// `OverlayStyle`): the capsule can no longer sit there pulsing on a stale
/// audio level while it is actually uploading or polishing.
final class RecordingOverlayPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let sessionTimerLabel = NSTextField(labelWithString: "0s")
    private let sessionStatusLabel = NSTextField(labelWithString: "")
    private let sessionColumn = NSStackView()
    private let waveformView = WaveformView()
    private var capsuleView: NSVisualEffectView?
    private var borderView: NSView?
    private var animator = WaveformAnimator()
    private let busyWaveform = IndeterminateWaveform()
    private var displayTimer: Timer?
    private var autoDismissTimer: Timer?

    private let capsuleHeight: CGFloat = OverlayMetrics.baseHeight
    private let hPadding: CGFloat = OverlayMetrics.horizontalPadding
    private let waveSize: CGFloat = OverlayMetrics.waveformSlot
    private let stackGap: CGFloat = OverlayMetrics.stackGap
    private var isShowing = false

    /// Current pipeline stage and the transcript streamed while listening.
    private var state: OverlayState = .listening
    private var liveText: String = ""
    private var resolved: OverlayStyle.Resolved = OverlayStyle.resolve(.listening, language: .english)

    // MARK: - Continuous dictation bookkeeping

    private var ledger = RelaySessionLedger()
    private var sessionStartedAt: Date?
    private var compactIdleThreshold: TimeInterval = 8
    private var lastActivityAt = Date()
    private var isCompact = false
    private var receipt: Receipt?
    private var borderFlash: (tint: OverlayStyle.Tint, until: Date)?
    private var pendingLevel: Float = 0
    private var busyPhase: Float = 0

    /// A short-lived confirmation in the session status column. Never replaces
    /// the text row — the user's words stay readable the whole time.
    private struct Receipt {
        let text: String
        let tint: OverlayStyle.Tint
        let expires: Date
    }

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

    /// Live on-device transcript while the user is speaking.
    func updateLiveText(_ text: String) {
        guard isShowing else { return }
        // An upload/polish stage may be running while the user is already
        // speaking the next segment: new words must not stomp that stage back
        // to "listening".
        let busy = state == .transcribing || state == .polishing
        if !busy {
            state = .listening
            liveText = text
            busyPhase = 0
            resolved = style(for: state)
        } else {
            liveText = text
        }
        lastActivityAt = Date()
        stopAutoDismiss()
        applyStyle()
        updateFrame(animated: true)
    }

    /// Cloud ASR is replacing the Apple result.
    func showTranscribing() {
        transition(to: .transcribing)
    }

    /// The LLM polish pass is running.
    func showPolishing() {
        transition(to: .polishing)
    }

    /// The final (possibly polished) text, revealed for a beat before it is
    /// injected. The checkmark replaces the old "✨ " text prefix.
    func showResult(_ text: String) {
        transition(to: .success, text: text)
    }

    /// Nothing was recognized.
    func showEmpty() {
        transition(to: .empty, clearLiveText: true)
    }

    /// A stage failed: say so in the capsule instead of only in the log, then
    /// get out of the way on its own.
    func showError(message: String? = nil) {
        transition(to: .error, clearLiveText: true, statusOverride: message, autoDismissAfter: 2.5)
    }

    // MARK: - Continuous dictation (relay session)

    /// Switches the capsule into the persistent session HUD. Called when a
    /// relay session opens; the placement does not change.
    func beginRelaySession(idleThreshold: TimeInterval) {
        ledger.reset()
        receipt = nil
        borderFlash = nil
        isCompact = false
        sessionStartedAt = Date()
        compactIdleThreshold = OverlayMetrics.compactIdleThreshold(idleThreshold: idleThreshold)
        lastActivityAt = Date()
        stopAutoDismiss()
        applyLayout()
        refreshSessionStatus()
        refreshSessionTimer()
        if isShowing {
            updateFrame(animated: true)
        } else {
            isShowing = true
            present()
        }
    }

    /// A segment started its work (an idle rotation). Only the counter moves —
    /// the stage itself is reported through `showTranscribing`/`showPolishing`.
    func noteSegmentStarted() {
        ledger.noteSegmentStarted()
        refreshSessionStatus()
    }

    /// A segment landed in the document: brief receipt, then back to normal.
    /// The receipt carries the segment number — the user maps receipts onto
    /// what they said.
    func noteSegmentInserted(characters: Int) {
        ledger.noteInserted(characters: characters)
        state = .listening
        resolved = style(for: state)
        setReceipt(text: OverlaySessionCopy.inserted(segment: ledger.segmentsInserted,
                                                     characters: characters,
                                                     language: overlayLanguage),
                   tint: .positive,
                   duration: OverlaySessionCopy.receiptDuration)
        flashBorder(.positive)
        lastActivityAt = Date()
        applyStyle()
    }

    /// The session's last segment (the one produced by the stop tap) landed.
    func noteFinalSegmentInserted(characters: Int) {
        ledger.noteSegmentStarted()
        ledger.noteInserted(characters: characters)
    }

    /// A rotation with no recognized words: nothing is uploaded or inserted.
    func noteSegmentSkipped() {
        ledger.noteSkipped()
        state = .listening
        resolved = style(for: state)
        setReceipt(text: OverlaySessionCopy.skipped(segment: ledger.segmentsStarted,
                                                    language: overlayLanguage),
                   tint: .caution,
                   duration: OverlaySessionCopy.skippedReceiptDuration)
        flashBorder(.caution)
        applyStyle()
    }

    /// A segment was recognized but never inserted (polish came back empty).
    /// Leaves a persistent chip: silence here would read as "it saved my words".
    func noteSegmentFailed() {
        ledger.noteFailed()
        state = .listening
        resolved = style(for: state)
        flashBorder(.critical)
        applyStyle()
    }

    /// Closes the session with a receipt — segments, characters, duration, and
    /// anything that did not make it in — then leaves on its own.
    func endRelaySession() {
        let startedAt = sessionStartedAt ?? Date()
        let summary = OverlaySessionSummary(
            segments: ledger.segmentsInserted,
            characters: ledger.characters,
            duration: Date().timeIntervalSince(startedAt),
            skipped: ledger.segmentsSkipped,
            failed: ledger.segmentsFailed
        )
        let text = summary.text(language: overlayLanguage)

        sessionStartedAt = nil
        state = .success
        liveText = text
        resolved = OverlayStyle.Resolved(statusText: text,
                                         waveform: .symbol("checkmark"),
                                         tint: .positive,
                                         prefersText: true,
                                         dimsTimer: true)
        receipt = nil
        isCompact = false
        applyLayout()
        applyStyle()
        flashBorder(.positive)
        refreshSessionStatus()

        if isShowing {
            updateFrame(animated: true)
        } else {
            isShowing = true
            present()
        }
        scheduleAutoDismiss(after: OverlaySessionCopy.summaryDuration)
    }

    /// Raw audio level in 0...1 — smoothed by the animator at display rate.
    func setAudioLevel(_ level: Float) {
        guard isShowing, displayTimer != nil else { return }
        // Any real signal counts as "the user is talking", which is what keeps
        // the session HUD expanded.
        if level > 0.02 { lastActivityAt = Date() }
        pendingLevel = level
    }

    func dismiss() {
        guard isShowing else { return }
        isShowing = false
        stopDisplayTimer()
        stopAutoDismiss()

        // The model value lands immediately and the fade is a layer animation:
        // the capsule can never be left stranded invisible if an animation is
        // dropped, and the geometry below is unaffected either way.
        alphaValue = 0
        let reduceMotion = self.reduceMotion
        let duration: TimeInterval = reduceMotion ? 0.12 : 0.22
        if let layer = contentView?.layer {
            layer.opacity = 0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1.0
            fade.toValue = 0.0
            fade.duration = duration
            fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
            layer.add(fade, forKey: "exitFade")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.orderOut(nil)
        }

        // Scale-down exit on the capsule layer — decorative, so it is skipped
        // when the user asked for reduced motion.
        guard !reduceMotion else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 0.9
        scale.duration = duration
        scale.timingFunction = CAMediaTimingFunction(name: .easeIn)
        capsuleView?.layer?.add(scale, forKey: "exitScale")
        capsuleView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.9, y: 0.9))
    }

    // MARK: - State transitions

    /// Single entry point for every stage change. When the capsule is already
    /// on screen it re-styles and re-flows in place; otherwise it presents
    /// itself (used by `showError` on a failed start).
    private func transition(
        to state: OverlayState,
        text: String? = nil,
        clearLiveText: Bool = false,
        statusOverride: String? = nil,
        autoDismissAfter: TimeInterval? = nil
    ) {
        self.state = state
        if clearLiveText { liveText = "" }
        if let text { liveText = text }
        resolved = style(for: state)
        if let statusOverride {
            resolved = OverlayStyle.Resolved(
                statusText: statusOverride,
                waveform: resolved.waveform,
                tint: resolved.tint,
                prefersText: false,
                dimsTimer: true
            )
        }
        scheduleAutoDismiss(after: autoDismissAfter)
        applyStyle()

        if isShowing {
            updateFrame(animated: true)
        } else {
            isShowing = true
            present()
        }
    }

    private func style(for state: OverlayState) -> OverlayStyle.Resolved {
        OverlayStyle.resolve(state, language: overlayLanguage)
    }

    private lazy var overlayLanguage: OverlayLanguage = OverlayStyle.language()

    /// What the capsule actually shows. The text row stays the in-progress
    /// words no matter which stage is running — the document is the transcript
    /// there, and the stage lives in the status column instead.
    private var displayText: String {
        let hasText = !liveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Nothing spoken yet: the status column already reports the stage,
        // so the text row stays empty instead of trailing a lone "…".
        guard state != .success else { return resolved.statusText }
        return hasText ? liveText : ""
    }

    // MARK: - Styling

    private func applyStyle() {
        label.stringValue = displayText
        renderActivitySlot()
        // The activity slot shows the *stage*; the border pulse is a separate,
        // event-level signal and must not repaint the waveform (a red level
        // meter would read as a broken microphone).
        waveformView.setTint(tintColor(for: resolved.tint))
        refreshLabelStyle()
        refreshBorder()
        refreshSessionStatus()
    }

    /// Text row emphasis. The document is the transcript, so the live words
    /// step back — and step back further while a stage is running, so nothing
    /// on screen can be mistaken for "the system is working" other than the
    /// status column.
    private func refreshLabelStyle() {
        let hasText = !liveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let busy = state == .transcribing || state == .polishing
        if hasText && busy {
            label.textColor = NSColor.white.withAlphaComponent(0.4)
        } else if hasText {
            label.textColor = NSColor.white.withAlphaComponent(0.78)
        } else {
            label.textColor = NSColor.white.withAlphaComponent(0.85)
        }
    }

    /// Border accent: an explicit flash wins, then the state's own accent.
    private var activeTint: OverlayStyle.Tint {
        borderFlash?.tint ?? resolved.tint
    }

    private func refreshBorder() {
        borderView?.layer?.borderColor = borderColor(for: activeTint).cgColor
    }

    /// A short accent pulse on the capsule edge — the "something just landed"
    /// signal that does not need a single pixel of the user's text.
    private func flashBorder(_ tint: OverlayStyle.Tint, duration: TimeInterval = 0.45) {
        borderFlash = (tint: tint, until: Date().addingTimeInterval(duration))
        refreshBorder()
    }

    private func setReceipt(text: String, tint: OverlayStyle.Tint, duration: TimeInterval) {
        receipt = Receipt(text: text, tint: tint, expires: Date().addingTimeInterval(duration))
    }

    /// Session status column. Priority: live receipt → unresolved-failure chip →
    /// current stage → segment counter. The failure chip outranks the stage so a
    /// lost segment is never hidden by a passing upload.
    private func refreshSessionStatus() {
        if let receipt {
            sessionStatusLabel.stringValue = receipt.text
            sessionStatusLabel.textColor = tintColor(for: receipt.tint).withAlphaComponent(0.95)
            return
        }
        if ledger.unacknowledgedFailures > 0 {
            sessionStatusLabel.stringValue = OverlaySessionCopy.failureLedger(
                ledger.unacknowledgedFailures, language: overlayLanguage)
            sessionStatusLabel.textColor = tintColor(for: .caution).withAlphaComponent(0.95)
            return
        }
        switch state {
        case .transcribing:
            sessionStatusLabel.stringValue = OverlaySessionCopy.uploading(language: overlayLanguage)
            sessionStatusLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        case .polishing:
            sessionStatusLabel.stringValue = OverlaySessionCopy.polishing(language: overlayLanguage)
            sessionStatusLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        case .success:
            sessionStatusLabel.stringValue = ""
            sessionStatusLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        default:
            sessionStatusLabel.stringValue = ledger.segmentsStarted > 0
                ? OverlaySessionCopy.segmentIndex(ledger.segmentsStarted, language: overlayLanguage)
                : ""
            sessionStatusLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        }
    }

    private func refreshSessionTimer() {
        guard let startedAt = sessionStartedAt else { return }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        sessionTimerLabel.stringValue = OverlayMetrics.elapsedLabel(seconds: seconds)
        let dim = resolved.dimsTimer || seconds < OverlayStyle.timerRevealSecond
        sessionTimerLabel.alphaValue = dim ? 0.35 : 1.0
    }

    private func tintColor(for tint: OverlayStyle.Tint) -> NSColor {
        switch tint {
        case .neutral: return NSColor.white.withAlphaComponent(0.9)
        case .dimmed: return NSColor.white.withAlphaComponent(0.62)
        case .positive: return NSColor.systemGreen
        case .caution: return NSColor.systemOrange
        case .critical: return NSColor.systemRed
        }
    }

    private func borderColor(for tint: OverlayStyle.Tint) -> NSColor {
        tint == .neutral
            ? NSColor.white.withAlphaComponent(0.1)
            : tintColor(for: tint).withAlphaComponent(0.45)
    }

    // MARK: - Internals

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
        effect.layer?.cornerRadius = OverlayMetrics.maxCornerRadius
        effect.layer?.masksToBounds = true
        effect.appearance = NSAppearance(named: .darkAqua)
        capsuleView = effect
        shadowHost.addSubview(effect)

        // Subtle inner border for depth
        let border = NSView(frame: contentView.bounds)
        border.autoresizingMask = [.width, .height]
        border.wantsLayer = true
        border.layer?.cornerRadius = OverlayMetrics.maxCornerRadius
        border.layer?.borderWidth = 0.5
        border.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        effect.addSubview(border)
        borderView = border

        // Layout: waveform + label
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = OverlayMetrics.stackGap
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

        // Session HUD trailing column: elapsed clock on top, segment status
        // underneath. Fixed width, right aligned — the capsule must not reflow
        // when "识别中…" becomes "✓ 已插入 · 24 字".
        sessionColumn.orientation = .vertical
        sessionColumn.alignment = .trailing
        sessionColumn.spacing = 1
        sessionColumn.translatesAutoresizingMaskIntoConstraints = false
        sessionColumn.isHidden = true

        sessionTimerLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        sessionTimerLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        sessionTimerLabel.alignment = .right

        sessionStatusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        sessionStatusLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        sessionStatusLabel.alignment = .right
        sessionStatusLabel.lineBreakMode = .byTruncatingTail
        sessionStatusLabel.maximumNumberOfLines = 1

        sessionColumn.addArrangedSubview(sessionTimerLabel)
        sessionColumn.addArrangedSubview(sessionStatusLabel)
        stack.addArrangedSubview(sessionColumn)

        NSLayoutConstraint.activate([
            waveformView.widthAnchor.constraint(equalToConstant: waveSize),
            waveformView.heightAnchor.constraint(equalToConstant: 32),
            sessionColumn.widthAnchor.constraint(equalToConstant: OverlayMetrics.sessionTrailingWidth),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: hPadding),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -hPadding),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
        ])
    }

    /// Session layout: one truncated line, so the type steps down a point to
    /// buy horizontal room instead of wrapping.
    private func applyLayout() {
        // The closing summary carries the whole receipt in its text, so the
        // status column would only repeat it.
        sessionColumn.isHidden = state == .success
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 14, weight: .medium)
    }

    /// Orders the capsule in: geometry and opacity land synchronously, the
    /// entry motion is a layer animation on top (so it can never strand the
    /// panel at a stale frame or at alpha 0).
    private func present() {
        let frame = preparedFrame()
        updateCornerRadius(for: frame.height, animated: false)
        // Undo the exit scale, if this capsule was already shown once.
        capsuleView?.layer?.setAffineTransform(.identity)

        let rise = NSRect(x: frame.minX, y: frame.minY - 14, width: frame.width, height: frame.height)
        setFrame(rise, display: false)
        alphaValue = 1
        setFrame(frame, display: false)
        orderFrontRegardless()
        startDisplayTimer()

        guard let layer = contentView?.layer else { return }
        layer.opacity = 1
        layer.transform = CATransform3DIdentity

        guard !reduceMotion else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0
        fade.toValue = 1.0
        fade.duration = 0.3
        layer.add(fade, forKey: "entryFade")

        let glide = CABasicAnimation(keyPath: "transform")
        glide.fromValue = NSValue(caTransform3D: CATransform3DMakeTranslation(0, -14, 0))
        glide.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        glide.duration = 0.35
        glide.timingFunction = CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.1)
        layer.add(glide, forKey: "entryGlide")
    }
    /// Target frame for the current text: fixed session width, wrapping height.
    private func preparedFrame() -> NSRect {
        if isCompact {
            // A narrow pill squeezes the flexible label out on its own: no
            // hide/animate bookkeeping, and the placement never moves.
            layoutLabel(for: OverlayMetrics.sessionCompactWidth, padding: OverlayMetrics.sessionInternalPadding)
            return centeredFrame(width: OverlayMetrics.sessionCompactWidth,
                                 height: OverlayMetrics.sessionCompactHeight)
        }
        let width = OverlayMetrics.sessionWidth(for: displayText,
                                                 trailingExtra: sessionTrailingExtraInUse)
        layoutLabel(for: width, padding: OverlayMetrics.internalPadding + sessionTrailingExtraInUse)
        return centeredFrame(width: width, height: OverlayMetrics.sessionHeight)
    }

    /// How much width the status column currently takes from the text row.
    private var sessionTrailingExtraInUse: CGFloat {
        state == .success ? 0 : OverlayMetrics.sessionTrailingExtra
    }

    /// Elastic width/height transition: a long sentence wraps and the capsule
    /// grows vertically instead of truncating.
    ///
    /// The frame is set synchronously — `animator()` is only a visual nicety
    /// that AppKit is free to drop, and a dropped frame animation must never
    /// leave the capsule at the width of a sentence the user already replaced.
    private func updateFrame(animated: Bool) {
        let frame = preparedFrame()
        updateCornerRadius(for: frame.height, animated: animated)

        let previousWidth = contentView?.bounds.width ?? frame.width
        setFrame(frame, display: true)

        guard animated, !reduceMotion,
              frame.width > 0, previousWidth > 0,
              let layer = contentView?.layer else { return }
        // Horizontal stretch from the old width: reads the same as the old
        // sliding window, but runs on the layer where it cannot be dropped.
        let stretch = CABasicAnimation(keyPath: "transform")
        stretch.fromValue = NSValue(caTransform3D:
            CATransform3DMakeScale(previousWidth / frame.width, 1, 1))
        stretch.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        stretch.duration = 0.25
        stretch.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(stretch, forKey: "widthStretch")
    }

    /// Keeps the capsule pill-shaped while it grows vertically — without this
    /// the corner radius froze at the single-line value and the shape read as a
    /// rounded rectangle.
    private func updateCornerRadius(for height: CGFloat, animated: Bool) {
        let radius = OverlayMetrics.cornerRadius(forHeight: height)
        for view in [capsuleView, borderView].compactMap({ $0 }) {
            guard let layer = view.layer, layer.cornerRadius != radius else { continue }
            if animated && !reduceMotion {
                let corner = CABasicAnimation(keyPath: "cornerRadius")
                corner.fromValue = layer.cornerRadius
                corner.toValue = radius
                corner.duration = 0.25
                corner.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(corner, forKey: "cornerRadius")
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.cornerRadius = radius
            CATransaction.commit()
        }
    }

    /// Gives the multi-line label a wrap width that matches the capsule's
    /// text area (AppKit needs this to compute a wrapped intrinsic height).
    private func layoutLabel(for width: CGFloat, padding: CGFloat = OverlayMetrics.internalPadding) {
        label.preferredMaxLayoutWidth = max(width - padding, 40)
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

    // MARK: - Display timer

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

    private func scheduleAutoDismiss(after interval: TimeInterval?) {
        stopAutoDismiss()
        guard let interval else { return }
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
        RunLoop.main.add(timer, forMode: .common)
        autoDismissTimer = timer
    }

    private func stopAutoDismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
    }

    /// Draws the activity slot for the current state. Called both on state
    /// changes and every display frame, so returning to `.listening` replaces
    /// the state symbol immediately instead of one frame late.
    private func renderActivitySlot() {
        switch resolved.waveform {
        case .symbol(let name):
            waveformView.setSymbol(name)
        case .level:
            let level = pendingLevel
            pendingLevel = 0
            let random = Float.random(in: 0...1)
            waveformView.setBars(animator.update(targetLevel: level, random: random))
        case .indeterminate:
            // No microphone to watch: a travelling bump keeps the capsule alive
            // instead of pulsing a level captured seconds ago.
            pendingLevel = 0
            waveformView.setBars(busyWaveform.bars(atPhase: busyPhase))
        }
    }

    private func tick() {
        // ~1.7 s for a full out-and-back sweep.
        busyPhase += 1.0 / 30.0 * 0.6
        renderActivitySlot()
        tickSessionState()
    }

    /// Per-frame bookkeeping for the session HUD: expire the receipt, release
    /// the border flash, and collapse the pill while the user is silent.
    private func tickSessionState() {
        if let receipt, Date() >= receipt.expires {
            self.receipt = nil
            refreshSessionStatus()
        }
        if let borderFlash, Date() >= borderFlash.until {
            self.borderFlash = nil
            refreshBorder()
        }
        refreshSessionTimer()

        // Only while listening: an in-flight upload/polish must stay legible.
        if state == .listening {
            let silent = Date().timeIntervalSince(lastActivityAt)
            setCompact(silent >= compactIdleThreshold)
        } else {
            setCompact(false)
        }
    }

    /// Collapses the persistent HUD to a slim pill while the user is silent so
    /// it stops competing with the page, and expands again on the first word.
    private func setCompact(_ compact: Bool) {
        guard compact != isCompact, isShowing else { return }
        isCompact = compact
        updateFrame(animated: true)
    }

    // MARK: - Accessibility

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
