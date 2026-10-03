import AppKit
import SwiftUI
import ServiceManagement

private let logger = FileLogger.shared

enum RecordingState {
    case idle
    case recording
    case processing
    case error
}

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    /// Dimmed, non-clickable first row: what the app is doing right now. A
    /// continuous-dictation session can run for minutes, so the menu bar is
    /// where the user confirms the microphone is still open.
    private var statusHeaderItem: NSMenuItem?
    /// The separator that follows the header row — hidden together with it so
    /// the menu never starts with a bare divider when no session is running.
    private var headerSeparatorItem: NSMenuItem?
    private var stopRelayItem: NSMenuItem?
    private var relayClock: Timer?
    private var relayStartedAt: Date?
    private var relaySegments = 0
    private var relayIsFinalizing = false

    var onQuit: (() -> Void)?
    var onSettings: (() -> Void)?
    var onToggleLoginItem: (() -> Void)?
    var onStopRelay: (() -> Void)?

    private var language: OverlayLanguage { OverlayStyle.language() }

    override init() {
        super.init()
        setupStatusItem()
        setupMenu()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "DoubleTapTalk")
            button.image?.isTemplate = true
        }

        statusItem?.menu = menu
    }

    private func setupMenu() {
        menu = NSMenu()

        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.isEnabled = false
        statusHeaderItem = header
        menu?.addItem(header)

        let headerSeparator = NSMenuItem.separator()
        headerSeparator.isHidden = true
        headerSeparatorItem = headerSeparator
        menu?.addItem(headerSeparator)

        let settingsItem = NSMenuItem(title: menuCopy(settings: "Settings…", zh: "设置…"),
                                       action: #selector(settingsClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu?.addItem(settingsItem)

        let stopItem = NSMenuItem(title: OverlaySessionCopy.endRelaySession(language: language),
                                  action: #selector(stopRelayClicked), keyEquivalent: "")
        stopItem.target = self
        stopItem.isHidden = true
        stopRelayItem = stopItem
        menu?.addItem(stopItem)

        menu?.addItem(NSMenuItem.separator())

        let loginItem = NSMenuItem(title: menuCopy(settings: "Launch at Login", zh: "登录时启动"),
                                   action: #selector(toggleLoginItemClicked), keyEquivalent: "")
        loginItem.target = self
        menu?.addItem(loginItem)

        menu?.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: menuCopy(settings: "Quit DoubleTapTalk", zh: "退出 DoubleTapTalk"),
                                  action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu?.addItem(quitItem)

        statusItem?.menu = menu
        updateLoginItemState()
    }

    /// Menu copy follows the same language choice as the overlay capsule, so a
    /// Chinese system never gets a half-translated menu.
    private func menuCopy(settings: String, zh: String) -> String {
        language == .simplifiedChinese ? zh : settings
    }

    func updateState(_ state: RecordingState) {
        logger.debug("Status bar state: \(state)")
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.statusItem?.button else { return }

            switch state {
            case .idle:
                // "mic" (outline): available but not in use. "mic.fill" is
                // reserved for the live session so the active state reads clearly.
                button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "DoubleTapTalk - Idle")
                button.image?.isTemplate = true
            case .recording:
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "DoubleTapTalk - Recording")
                button.image?.isTemplate = true
            case .processing:
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "DoubleTapTalk - Processing")
                button.image?.isTemplate = true
            case .error:
                button.image = NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: "DoubleTapTalk - Error")
                button.image?.isTemplate = true
            }
        }
    }

    // MARK: - Continuous dictation

    /// Opens the relay header: live segment count + elapsed clock, plus the
    /// menu item that ends the session without reaching for the hotkey.
    func beginRelaySession() {
        relayStartedAt = Date()
        relaySegments = 0
        relayIsFinalizing = false
        stopRelayItem?.isHidden = false
        refreshRelayHeader()
        startRelayClock()
    }

    func updateRelayProgress(segments: Int) {
        relaySegments = max(segments, 0)
        refreshRelayHeader()
    }

    /// The stop tap landed: the last segment is still being processed, so the
    /// header keeps reporting but the "end" item goes away (nothing left to end).
    func markRelayFinalizing() {
        relayIsFinalizing = true
        stopRelayItem?.isHidden = true
        refreshRelayHeader()
    }

    func endRelaySession() {
        relayStartedAt = nil
        relayIsFinalizing = false
        stopRelayClock()
        stopRelayItem?.isHidden = true
        setHeader(nil)
    }

    private func refreshRelayHeader() {
        guard let startedAt = relayStartedAt else {
            setHeader(nil)
            return
        }
        let clock = OverlayMetrics.sessionDurationLabel(
            seconds: Int(Date().timeIntervalSince(startedAt)))
        let text = relayIsFinalizing
            ? OverlaySessionCopy.relayFinalizing(language: language)
            : OverlaySessionCopy.relayHeader(segments: relaySegments, clock: clock, language: language)
        setHeader(text)
    }

    /// The clock in the header is the only reason to refresh while nothing else
    /// happens — one cheap timer, torn down with the session.
    private func startRelayClock() {
        stopRelayClock()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshRelayHeader()
        }
        RunLoop.main.add(timer, forMode: .common)
        relayClock = timer
    }

    private func stopRelayClock() {
        relayClock?.invalidate()
        relayClock = nil
    }

    private func setHeader(_ text: String?) {
        guard let statusHeaderItem else { return }
        statusHeaderItem.title = text ?? ""
        statusHeaderItem.isHidden = (text == nil)
        // Keep the buddy separator in lockstep so an idle menu starts with
        // "Settings…" instead of a floating divider.
        headerSeparatorItem?.isHidden = (text == nil)
    }

    // MARK: - Menu state

    func updateLoginItemState() {
        guard let menu,
              let loginItem = menu.items.first(where: { $0.action == #selector(toggleLoginItemClicked) }) else { return }

        if #available(macOS 13.0, *) {
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    @objc private func settingsClicked() {
        logger.debug("Status bar: Settings clicked")
        onSettings?()
    }

    @objc private func stopRelayClicked() {
        logger.info("Status bar: End continuous dictation clicked")
        onStopRelay?()
    }

    @objc private func toggleLoginItemClicked() {
        logger.debug("Status bar: Toggle login item clicked")
        onToggleLoginItem?()
    }

    @objc private func quitClicked() {
        logger.info("Status bar: Quit clicked")
        onQuit?()
    }
}
