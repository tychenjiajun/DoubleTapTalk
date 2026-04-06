import SwiftUI
import ServiceManagement

@main
struct VoiceKeyApp: App {
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
    private var audioRecorder: AudioRecorder?
    private var asrService: ASRService?
    private var textInjectionService: TextInjectionService?
    private var logger = FileLogger.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.log("=== VoiceKey Started ===")
        logger.debug("PID: \(ProcessInfo.processInfo.processIdentifier)")
        logger.debug("Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")")
        logger.debug("Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")
        
        // Initialize services
        logger.debug("Initializing TextInjectionService...")
        textInjectionService = TextInjectionService()
        logger.debug("Initializing AudioRecorder...")
        audioRecorder = AudioRecorder()
        logger.debug("Initializing ASRService...")
        asrService = ASRService()
        
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
        statusBarController?.onStartRecording = { [weak self] in
            self?.startRecording()
        }
        statusBarController?.onStopRecording = { [weak self] in
            self?.stopRecording()
        }
        
        // Initialize hotkey service
        hotkeyService = HotkeyService()
        hotkeyService?.onHotkeyPressed = { [weak self] in
            self?.startRecording()
        }
        hotkeyService?.onHotkeyReleased = { [weak self] in
            self?.stopRecording()
        }
        hotkeyService?.start()
        
        // Update status bar to idle state
        statusBarController?.updateState(.idle)
        logger.log("Ready - click menu to start/stop recording")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        hotkeyService?.stop()
        _ = audioRecorder?.stopRecording()
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
        guard let audioRecorder = audioRecorder else { return }
        
        do {
            logger.log("Starting recording...")
            try audioRecorder.startRecording()
            statusBarController?.updateState(.recording)
            logger.log("Recording started")
        } catch {
            logger.log("Failed to start recording: \(error)")
            statusBarController?.updateState(.error)
        }
    }
    
    private func stopRecording() {
        guard let audioRecorder = audioRecorder else { return }
        
        let audioURL = audioRecorder.stopRecording()
        statusBarController?.updateState(.processing)
        logger.log("Recording stopped")
        
        guard let url = audioURL else {
            logger.log("No audio URL returned")
            statusBarController?.updateState(.idle)
            return
        }
        
        Task {
            do {
                logger.log("Transcribing audio from: \(url.path)")
                let text = try await asrService?.transcribe(audioURL: url)
                logger.log("Transcription result: '\(text ?? "nil")'")
                await MainActor.run {
                    if let text = text, !text.isEmpty {
                        logger.log("Injecting text: \(text)")
                        textInjectionService?.injectText(text)
                    } else {
                        logger.log("Empty or nil text result")
                    }
                    statusBarController?.updateState(.idle)
                }
            } catch {
                await MainActor.run {
                    logger.log("Transcription FAILED: \(error)")
                    statusBarController?.updateState(.error)
                }
            }
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: url)
        }
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
    private let queue = DispatchQueue(label: "com.voicekey.logger", attributes: .concurrent)
    
    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        logURL = caches.appendingPathComponent("VoiceKey.log")
        info("=== Logger initialized, log file: \(logURL.path) ===")
    }
    
    func log(_ message: String, level: LogLevel = .info) {
        writeLog(message, level: level)
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