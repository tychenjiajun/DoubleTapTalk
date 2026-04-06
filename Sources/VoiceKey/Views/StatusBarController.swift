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
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    
    override init() {
        super.init()
        setupStatusItem()
        setupMenu()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VoiceKey")
            button.image?.isTemplate = true
        }
        
        statusItem?.menu = menu
    }
    
    private func setupMenu() {
        menu = NSMenu()
        
        // Recording controls
        let recordItem = NSMenuItem(title: "Start Recording", action: #selector(startRecordingClicked), keyEquivalent: "r")
        recordItem.target = self
        menu?.addItem(recordItem)
        
        let stopItem = NSMenuItem(title: "Stop Recording", action: #selector(stopRecordingClicked), keyEquivalent: "s")
        stopItem.target = self
        menu?.addItem(stopItem)
        
        menu?.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(settingsClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu?.addItem(settingsItem)
        
        menu?.addItem(NSMenuItem.separator())
        
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItemClicked), keyEquivalent: "")
        loginItem.target = self
        menu?.addItem(loginItem)
        
        menu?.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit VoiceKey", action: #selector(quitClicked), keyEquivalent: "q")
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
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VoiceKey - Idle")
                button.image?.isTemplate = true
            case .recording:
                button.image = NSImage(systemSymbolName: "mic.badge.plus", accessibilityDescription: "VoiceKey - Recording")
                button.image?.isTemplate = true
            case .processing:
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "VoiceKey - Processing")
                button.image?.isTemplate = true
            case .error:
                button.image = NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: "VoiceKey - Error")
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
    
    @objc private func startRecordingClicked() {
        logger.info("Status bar: Start recording clicked")
        onStartRecording?()
    }
    
    @objc private func stopRecordingClicked() {
        logger.info("Status bar: Stop recording clicked")
        onStopRecording?()
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