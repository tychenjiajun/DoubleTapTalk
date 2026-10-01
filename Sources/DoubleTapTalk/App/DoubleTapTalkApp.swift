import SwiftUI
import ServiceManagement
import AppKit
import AVFoundation

@main
struct DoubleTapTalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var hotkeyService: HotkeyService?
    private var textInjectionService: TextInjectionService?
    private var appleSpeechBackend: AppleSpeechBackend?
    private lazy var recordingOverlay = RecordingOverlayPanel()
    private var logger = FileLogger.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("=== DoubleTapTalk Started ===")
        logger.debug("PID: \(ProcessInfo.processInfo.processIdentifier)")
        logger.debug("Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")")
        logger.debug("Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")
        
        // Check Accessibility permission
        if !AccessibilityService.shared.hasAccessibilityPermission() {
            logger.warning("Accessibility permission not granted — context reading will be limited")
            logger.info("Users can grant permission in Settings > Privacy & Security > Accessibility")
        } else {
            logger.info("Accessibility permission granted — full context reading enabled")
        }
        
        // Initialize services
        logger.debug("Initializing TextInjectionService...")
        textInjectionService = TextInjectionService()
        
        // Initialize status bar
        statusBarController = StatusBarController()
        statusBarController?.onQuit = {
            NSApplication.shared.terminate(nil)
        }
        statusBarController?.onSettings = { [weak self] in
            self?.showSettings()
        }
        statusBarController?.onToggleLoginItem = { [weak self] in
            self?.toggleLoginItem()
        }
        
        // Initialize hotkey service
        hotkeyService = HotkeyService()
        hotkeyService?.onHotkeyPressed = { [weak self] in
            self?.startRecording()
        }
        hotkeyService?.onHotkeyReleased = { [weak self] polish in
            self?.stopRecording(polish: polish)
        }
        hotkeyService?.start()
        
        // Update status bar to idle state
        statusBarController?.updateState(.idle)
        logger.info("Ready - double-tap Control to start/stop recording")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        hotkeyService?.stop()
    }
    
    private func showSettings() {
        logger.debug("Opening settings window")
        let settingsWindow = SettingsWindowController()
        settingsWindow.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func toggleLoginItem() {
        if #available(macOS 13.0, *) {
            let currentStatus = SMAppService.mainApp.status
            logger.debug("Current login item status: \(currentStatus)")
            do {
                if currentStatus == .enabled {
                    logger.info("Disabling launch at login")
                    try SMAppService.mainApp.unregister()
                } else {
                    logger.info("Enabling launch at login")
                    try SMAppService.mainApp.register()
                }
                statusBarController?.updateLoginItemState()
                logger.debug("Login item toggled successfully")
            } catch {
                logger.error("Failed to toggle login item: \(error)")
            }
        } else {
            logger.warning("Launch at login not supported on this macOS version")
        }
    }
    
    private func startRecording() {
        Task {
            // Check and request microphone permission if needed
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            logger.info("Microphone permission status: \(status)\(status.rawValue)")
            
            if status == .notDetermined {
                logger.info("Microphone permission not determined, requesting access...")
                let granted = await MicrophonePermissionService.shared.requestPermission()
                
                logger.info("Microphone permission request result: \(granted)")
                
                if !granted {
                    await MainActor.run {
                        logger.error("Microphone permission denied — cannot record audio")
                        logger.info("Please grant permission in System Settings > Privacy & Security > Microphone")
                        self.showPermissionDeniedAlert()
                        statusBarController?.updateState(.idle)
                    }
                    return
                }
                
                await MainActor.run {
                    logger.info("Microphone permission granted")
                }
            } else if status == .denied || status == .restricted {
                await MainActor.run {
                    logger.error("Microphone permission already denied/restricted")
                    logger.info("Please grant permission in System Settings > Privacy & Security > Microphone")
                    self.showPermissionDeniedAlert()
                    statusBarController?.updateState(.idle)
                }
                return
            }
            
            // Proceed with recording — Apple streaming is the only backend
            do {
                try await startAppleStreaming()
            } catch {
                await MainActor.run {
                    logger.info("Failed to start recording: \(error)")
                    recordingOverlay.dismiss()
                    statusBarController?.updateState(.error)
                }
            }
        }
    }
    
    /// Starts on-device streaming recognition (Apple). Shows the overlay and
    /// streams live partial text + audio levels into it.
    private func startAppleStreaming() async throws {
        logger.info("Starting Apple streaming recognition...")
        
        guard await AppleSpeechBackend.requestPermission() else {
            await MainActor.run {
                logger.error("Speech recognition permission denied")
                self.showSpeechPermissionDeniedAlert()
                statusBarController?.updateState(.idle)
            }
            return
        }
        
        await MainActor.run {
            recordingOverlay.show()
        }
        
        let backend = AppleSpeechBackend()
        backend.onPartialText = { [weak self] text in
            Task { @MainActor in self?.recordingOverlay.updateText(text) }
        }
        backend.onAudioLevel = { [weak self] level in
            Task { @MainActor in self?.recordingOverlay.setAudioLevel(level) }
        }
        backend.onError = { message in
            FileLogger.shared.error("Apple recognition error: \(message)")
        }
        
        // Resolve on the main thread (TIS requires it) — when language is "auto",
        // the active input method decides: Chinese IME → zh-CN, English → en-US.
        let inputMethodLang = await MainActor.run {
            InputMethodLanguage.currentLanguageCode()
        }
        logger.info("Input method language: \(inputMethodLang ?? "unknown")")
        
        try backend.start(language: DoubleTapTalkSettings.shared.language, inputMethodLanguage: inputMethodLang)
        appleSpeechBackend = backend
        
        await MainActor.run {
            statusBarController?.updateState(.recording)
            logger.info("Apple streaming recognition started")
        }
    }
    
    private func showSpeechPermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Speech Recognition Permission Required"
        alert.informativeText = "DoubleTapTalk needs speech recognition permission for on-device transcription. Please grant it in System Settings > Privacy & Security > Speech Recognition, then try again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func showPermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone Permission Required"
        alert.informativeText = "DoubleTapTalk needs microphone access to record audio. Please grant permission in System Settings > Privacy & Security > Microphone, then try again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func stopRecording(polish: Bool = false) {
        statusBarController?.updateState(.processing)
        logger.info("Recording stopped")
        
        guard let backend = appleSpeechBackend else {
            statusBarController?.updateState(.idle)
            return
        }
        appleSpeechBackend = nil
        
        Task {
            let rawText = await backend.stop()
            await MainActor.run {
                recordingOverlay.updateText("Polishing…")
            }
            await finalize(rawText: rawText, polish: polish)
        }
    }
    
    /// Shared tail (DRY): polish → ✨ reveal (when changed) → inject → dismiss overlay.
    private func finalize(rawText: String, polish: Bool) async {
        let text = await PolishProcessor().process(
            rawText: rawText,
            settings: LLMSettings.current(),
            polishEnabled: polish
        )
        
        // "✨ what changed" moment (borrowed from voice-input-dist): when the
        // polish pass actually changed the text, hold the result in the overlay
        // for a beat so the user sees the edit before it lands.
        let wasChanged = !text.isEmpty && text != rawText
        
        await MainActor.run {
            if text.isEmpty {
                recordingOverlay.updateText("未识别到语音")
            } else if wasChanged {
                recordingOverlay.updateText("✨ \(text)")
            }
        }
        
        if wasChanged || text.isEmpty {
            // Reveal the polish result (1s) or show the empty-result hint briefly (0.8s)
            try? await Task.sleep(nanoseconds: text.isEmpty ? 800_000_000 : 1_000_000_000)
        }
        
        await MainActor.run {
            if !text.isEmpty {
                logger.info("Injecting text: \(text)")
                textInjectionService?.injectText(text)
                NSSound(named: "Pop")?.play()
            } else {
                logger.info("Empty or nil text result")
            }
            recordingOverlay.dismiss()
            statusBarController?.updateState(.idle)
        }
        
        // Clean up is not needed — Apple streaming never writes audio files.
    }
}

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

class FileLogger {
    static let shared = FileLogger()
    private let logURL: URL
    private let queue = DispatchQueue(label: "com.doubletaptalk.logger", attributes: .concurrent)
    
    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        logURL = caches.appendingPathComponent("DoubleTapTalk.log")
        info("=== Logger initialized, log file: \(logURL.path) ===")
    }
    
    func info(_ message: String) {
        writeLog(message, level: .info)
    }
    
    func debug(_ message: String) {
        writeLog(message, level: .debug)
    }
    
    func warning(_ message: String) {
        writeLog(message, level: .warning)
    }
    
    func error(_ message: String) {
        writeLog(message, level: .error)
    }
    
    private func writeLog(_ message: String, level: LogLevel) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let thread = Thread.isMainThread ? "[Main]" : "[BgThread]"
            let line = "[\(timestamp)] [\(level.rawValue)] \(thread) \(message)\n"
            
            var content = ""
            if let existing = try? String(contentsOf: self.logURL, encoding: .utf8) {
                content = existing
            }
            content += line
            
            try? content.write(to: self.logURL, atomically: true, encoding: .utf8)
            print("[\(level.rawValue)] \(message)")
        }
    }
    
    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            try? "".write(to: self!.logURL, atomically: true, encoding: .utf8)
        }
    }
    
    func getLogContent() -> String {
        return (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    }
}