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
    
    var onQuit: (() -> Void)?
    var onSettings: (() -> Void)?
    var onToggleLoginItem: (() -> Void)?
    
    override init() {
        super.init()
        setupStatusItem()
        setupMenu()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "DoubleTapTalk")
            button.image?.isTemplate = true
        }
        
        statusItem?.menu = menu
    }
    
    private func setupMenu() {
        menu = NSMenu()
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(settingsClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu?.addItem(settingsItem)
        
        menu?.addItem(NSMenuItem.separator())
        
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItemClicked), keyEquivalent: "")
        loginItem.target = self
        menu?.addItem(loginItem)
        
        menu?.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit DoubleTapTalk", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu?.addItem(quitItem)
        
        statusItem?.menu = menu
        updateLoginItemState()
    }
    
    func updateState(_ state: RecordingState) {
        logger.debug("Status bar state: \(state)")
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.statusItem?.button else { return }
            
            switch state {
            case .idle:
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "DoubleTapTalk - Idle")
                button.image?.isTemplate = true
            case .recording:
                button.image = NSImage(systemSymbolName: "mic.badge.plus", accessibilityDescription: "DoubleTapTalk - Recording")
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
    
    func updateLoginItemState() {
        guard let loginItem = menu?.items.first(where: { $0.action == #selector(toggleLoginItemClicked) }) else { return }
        
        if #available(macOS 13.0, *) {
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }
    
    @objc private func settingsClicked() {
        logger.debug("Status bar: Settings clicked")
        onSettings?()
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