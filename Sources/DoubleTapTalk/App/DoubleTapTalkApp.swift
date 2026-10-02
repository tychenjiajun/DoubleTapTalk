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
    /// Continuous relay dictation session (nil when relay mode is off).
    private var relaySession: ContinuousDictationSession?
    /// Serializes segment insertions so rotated segments land in order even
    /// though their cloud-ASR work finishes at different times.
    private let relayChain = OrderedTaskChain()
    /// Guards `dictationGeneration`, `activeGeneration` + `segmentHistory`:
    /// enqueues arrive from the session's emission chain and from
    /// stopRecording's task on different executors (NSLock — critical sections
    /// are non-blocking).
    private let relayLock = NSLock()
    /// Monotonic per-dictation id. Every result carries the id of the session
    /// that produced it, and stale results are dropped instead of being
    /// injected into whatever the user is doing now.
    private var dictationGeneration = 0
    /// Generation of the dictation currently being recorded (what `stop`
    /// finalizes).
    private var activeGeneration = 0
    /// Inserted results of earlier segments in the current dictation session,
    /// fed into each refinement prompt for consistency (capped inside the prompt).
    private var segmentHistory: [String] = []
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
        hotkeyService?.onHotkeyReleased = { [weak self] in
            self?.stopRecording()
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
            let generation = beginDictation()
            resetSegmentHistory()

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
            
            // Proceed with recording — Apple streaming is the only backend.
            // Continuous (relay) mode keeps the mic open across segments when enabled.
            do {
                if DoubleTapTalkSettings.shared.relayEnabled {
                    try await startRelayStreaming(generation: generation)
                } else {
                    try await startAppleStreaming()
                }
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
    
    /// Continuous dictation: one persistent engine + tap, segments rotated on
    /// idle silence, every rotated segment transcribed via cloud ASR (with
    /// Apple fallback) and inserted without disturbing the live overlay.
    private func startRelayStreaming(generation: Int) async throws {
        logger.info("Starting continuous relay dictation...")

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

        let session = ContinuousDictationSession(idleThreshold: DoubleTapTalkSettings.shared.relayIdleThreshold)
        session.onLiveText = { [weak self] text in
            Task { @MainActor in self?.recordingOverlay.updateText(text) }
        }
        session.onAudioLevel = { [weak self] level in
            Task { @MainActor in self?.recordingOverlay.setAudioLevel(level) }
        }
        session.onError = { message in
            FileLogger.shared.error("Relay recognition error: \(message)")
        }
        session.onSegmentTranscript = { [weak self] result in
            // Synchronous on purpose: the session's emission chain (and stop())
            // awaits this callback, so ordering is preserved end-to-end.
            self?.enqueueRelaySegment(result, final: false, generation: generation)
        }

        // Resolve on the main thread (TIS requires it).
        let inputMethodLang = await MainActor.run {
            InputMethodLanguage.currentLanguageCode()
        }
        logger.info("Input method language: \(inputMethodLang ?? "unknown")")

        try session.start(language: DoubleTapTalkSettings.shared.language, inputMethodLanguage: inputMethodLang)
        relaySession = session

        await MainActor.run {
            statusBarController?.updateState(.recording)
            logger.info("Relay dictation started")
        }
    }

    private func stopRecording() {
        statusBarController?.updateState(.processing)
        logger.info("Recording stopped")

        // Captured now: any result produced from here on is only allowed to be
        // injected while this is still the newest dictation.
        let generation = generationSnapshot()

        // Relay mode: finalize the whole session; already-rotated segments are
        // inserted in order before the final segment is refined + injected.
        if let session = relaySession {
            relaySession = nil
            Task {
                // stop() delivers all rotated segments (in order) before it
                // returns, so enqueuing the final one here lands it last.
                let result = await session.stop()
                self.enqueueRelaySegment(result, final: true, generation: generation)
            }
            return
        }

        guard let backend = appleSpeechBackend else {
            statusBarController?.updateState(.idle)
            return
        }
        appleSpeechBackend = nil
        
        Task {
            let appleText = await backend.stop()
            let recordingURL = backend.recordingFileURL

            // Cloud transcription (OpenAI-compatible ASR) of the recorded audio
            // replaces the final text; Apple's result is the fallback. Skip
            // upload when Apple recognized no words — no blank audio to ASR.
            let asr = ASRSettings.current()
            var rawText = appleText
            let hasWords = !appleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if asr.enabled, hasWords {
                if let recordingURL = recordingURL {
                    await MainActor.run {
                        guard self.isCurrentGeneration(generation) else { return }
                        self.recordingOverlay.updateText("云端识别中…")
                    }
                    if let cloudText = await CloudTranscriptionService.shared.transcribe(fileURL: recordingURL, settings: asr) {
                        logger.info("Using cloud transcription (Apple result kept as fallback)")
                        rawText = cloudText
                    } else {
                        logger.info("Cloud transcription unavailable — falling back to Apple result")
                    }
                } else {
                    logger.warning("No recording file available — using Apple result")
                    await MainActor.run {
                        guard self.isCurrentGeneration(generation) else { return }
                        self.recordingOverlay.updateText("Polishing…")
                    }
                }
            } else {
                if asr.enabled {
                    logger.info("No words recognized by Apple — skipping cloud upload")
                }
                await MainActor.run {
                    guard self.isCurrentGeneration(generation) else { return }
                    self.recordingOverlay.updateText("Polishing…")
                }
            }

            await finalize(rawText: rawText, generation: generation)
        }
    }

    // MARK: - Dictation generations

    /// Starts a new dictation session and returns its generation id.
    @discardableResult
    private func beginDictation() -> Int {
        relayLock.lock()
        defer { relayLock.unlock() }
        dictationGeneration += 1
        activeGeneration = dictationGeneration
        return dictationGeneration
    }

    /// Generation of the dictation currently being recorded. `stopRecording`
    /// captures this *before* its async work starts so a later session can't
    /// rewrite what the result belongs to.
    private func generationSnapshot() -> Int {
        relayLock.lock()
        defer { relayLock.unlock() }
        return activeGeneration
    }

    /// True while `generation` is still the newest dictation. Cloud ASR (which
    /// can take tens of seconds) and refinement can outlive a session; their
    /// results must never be injected into a later one.
    private func isCurrentGeneration(_ generation: Int) -> Bool {
        relayLock.lock()
        defer { relayLock.unlock() }
        return generation == dictationGeneration
    }

    // MARK: - Relay segment output

    /// Appends segment work to the ordered chain: every rotated segment is
    /// cloud-transcribed + refined + inserted in order, and the final segment
    /// (flagged `final`) runs last, reusing the classic finalize() reveal flow.
    ///
    /// Stale work (a session that has since ended) is dropped here, before it
    /// can touch the overlay, the history or the user's cursor.
    private func enqueueRelaySegment(_ result: ContinuousDictationSession.SegmentTranscript, final: Bool, generation: Int) {
        relayChain.enqueue { [weak self] in
            guard let self else { return }
            guard self.isCurrentGeneration(generation) else {
                self.logger.info("Dropping stale relay segment from session \(generation)")
                return
            }
            if final {
                await self.finishRelay(finalResult: result, generation: generation)
            } else {
                await self.insertRelaySegment(result, generation: generation)
            }
        }
    }

    /// Fresh history for a new dictation session, ordered behind any
    /// still-processing segments of the previous one (a lingering chain must
    /// never append into the new session's history). The reset itself takes
    /// `relayLock`, like every other `segmentHistory` access.
    private func resetSegmentHistory() {
        relayChain.enqueue { [weak self] in
            self?.clearSegmentHistory()
        }
    }

    /// Sync helper so the lock is taken outside the async closure (NSLock is
    /// unavailable from async contexts) — same pattern as the session's
    /// `claimForStop`.
    private func clearSegmentHistory() {
        relayLock.lock()
        segmentHistory = []
        relayLock.unlock()
    }

    private func segmentHistorySnapshot() -> [String] {
        relayLock.lock()
        defer { relayLock.unlock() }
        return segmentHistory
    }

    private func appendSegmentHistory(_ text: String) {
        relayLock.lock()
        segmentHistory.append(text)
        relayLock.unlock()
    }

    /// Single injection point: both the classic finalize() flow and relay
    /// intermediate segments land text here (PolishProcessor is the single
    /// polish point feeding it — see AGENTS.md).
    private func inject(_ text: String) {
        logger.info("Injecting text: \(text)")
        textInjectionService?.injectText(text)
        NSSound(named: "Pop")?.play()
    }

    /// Intermediate segment: cloud ASR with Apple fallback, then LLM
    /// refinement (when enabled) using earlier segments as context, then inject
    /// quietly — never touches the overlay or the live segment. Segments with
    /// no words recognized by Apple are skipped (no blank audio to ASR).
    private func insertRelaySegment(_ result: ContinuousDictationSession.SegmentTranscript, generation: Int) async {
        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.info("Relay segment: no words recognized by Apple — skipping")
            return
        }
        var text = result.text
        let asr = ASRSettings.current()
        if asr.enabled, let url = result.recordingFileURL {
            if let cloudText = await CloudTranscriptionService.shared.transcribe(fileURL: url, settings: asr) {
                text = cloudText
                logger.info("Relay segment: cloud transcription used")
            } else {
                logger.info("Relay segment: cloud unavailable — using Apple result")
            }
        }

        // Refinement runs when the LLM is enabled+configured — automatically,
        // no tap distinction needed.
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = await PolishProcessor().process(
                rawText: text,
                settings: LLMSettings.current(),
                previousSegments: segmentHistorySnapshot()
            )
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard isCurrentGeneration(generation) else {
            logger.info("Relay segment finished after session \(generation) ended — dropping")
            return
        }
        appendSegmentHistory(text)
        logger.info("Relay segment injecting: \(text)")
        let toInject = text
        await MainActor.run {
            guard self.isCurrentGeneration(generation) else { return }
            self.inject(toInject)
        }
    }

    /// Final segment: cloud ASR (fallback Apple) then the classic refine →
    /// reveal → inject → dismiss flow, with earlier segments as context. No
    /// upload when Apple recognized no words.
    private func finishRelay(finalResult: ContinuousDictationSession.SegmentTranscript, generation: Int) async {
        var rawText = finalResult.text
        let asr = ASRSettings.current()
        let hasWords = !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if asr.enabled, hasWords, let url = finalResult.recordingFileURL {
            await MainActor.run {
                guard self.isCurrentGeneration(generation) else { return }
                self.recordingOverlay.updateText("云端识别中…")
            }
            if let cloudText = await CloudTranscriptionService.shared.transcribe(fileURL: url, settings: asr) {
                rawText = cloudText
            } else {
                logger.info("Relay final: cloud unavailable — using Apple result")
            }
        } else {
            if asr.enabled {
                logger.info("Relay final: no words recognized by Apple — skipping cloud upload")
            }
            await MainActor.run {
                guard self.isCurrentGeneration(generation) else { return }
                self.recordingOverlay.updateText("Polishing…")
            }
        }
        await finalize(rawText: rawText, previousSegments: segmentHistorySnapshot(), generation: generation)
    }

    /// Shared tail (DRY): refine (when enabled) → ✨ reveal (when changed) →
    /// inject → dismiss overlay. Every step is generation-guarded: a stale
    /// result must neither overwrite the overlay nor inject into the cursor.
    private func finalize(rawText: String, previousSegments: [String] = [], generation: Int) async {
        guard isCurrentGeneration(generation) else {
            logger.info("Dictation \(generation) is stale — dropping result instead of injecting")
            return
        }

        let text = await PolishProcessor().process(
            rawText: rawText,
            settings: LLMSettings.current(),
            previousSegments: previousSegments
        )
        
        // "✨ what changed" moment (borrowed from voice-input-dist): when the
        // polish pass actually changed the text, hold the result in the overlay
        // for a beat so the user sees the edit before it lands.
        let wasChanged = !text.isEmpty && text != rawText
        
        await MainActor.run {
            guard self.isCurrentGeneration(generation) else { return }
            if text.isEmpty {
                self.recordingOverlay.updateText("未识别到语音")
            } else if wasChanged {
                self.recordingOverlay.updateText("✨ \(text)")
            }
        }
        
        if wasChanged || text.isEmpty {
            // Reveal the polish result (1s) or show the empty-result hint briefly (0.8s)
            try? await Task.sleep(nanoseconds: text.isEmpty ? 800_000_000 : 1_000_000_000)
        }
        
        await MainActor.run {
            guard self.isCurrentGeneration(generation) else {
                logger.info("Dictation \(generation) ended while finalizing — overlay left untouched")
                return
            }
            if !text.isEmpty {
                self.inject(text)
            } else {
                logger.info("Empty or nil text result")
            }
            self.recordingOverlay.dismiss()
            self.statusBarController?.updateState(.idle)
        }
        
        // Cleanup: WAV recordings only exist when Cloud Transcription is
        // enabled (RecordingFileWriter is gated on it, and pruned to the newest
        // 20 on finish); the rest stay in
        // ~/Library/Application Support/DoubleTapTalk/Recordings until deleted
        // from Settings.
    }
}

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

class FileLogger: @unchecked Sendable {
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