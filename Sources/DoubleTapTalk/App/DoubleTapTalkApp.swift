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
    /// Continuous relay dictation session (nil when relay mode is off).
    private var relaySession: ContinuousDictationSession?
    /// True from the moment the stop tap lands until the last segment is in —
    /// decides whether the capsule closes with a session summary.
    private var relayIsFinalizing = false
    /// Segments that actually landed, mirrored into the menu bar header.
    private var relaySegmentsInserted = 0
    /// Characters actually inserted this relay session, for the closing summary.
    private var relaySessionChars = 0
    /// When the relay session's mic opened — the summary reports total seconds.
    private var relaySessionStartedAt: Date?
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
        // A relay session can run for minutes; the menu bar is the always-there
        // place to confirm the mic is open and to end it without the hotkey.
        statusBarController?.onStopRelay = { [weak self] in
            self?.hotkeyService?.requestStop()
        }
        
        // Initialize hotkey service
        hotkeyService = HotkeyService()
        hotkeyService?.onHotkeyPressed = { [weak self] in
            self?.startRecording()
        }
        hotkeyService?.onHotkeyReleased = { [weak self] in
            self?.stopRecording()
        }
        hotkeyService?.onBackspaceWhileRecording = { [weak self] in
            self?.stopRelayViaBackspace()
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
            // A new dictation always starts clean: a relay session that was
            // abandoned mid-finalize must not leave its summary armed for the
            // next dictation.
            relayIsFinalizing = false
            relaySegmentsInserted = 0
            relaySessionChars = 0
            relaySessionStartedAt = nil

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
            // Proceed with recording — the relay (continuous) engine is the one
            // and only mode: microphone stays open, segments rotate on idle.
            do {
                try await startRelayStreaming(generation: generation)
            } catch {
                await MainActor.run {
                    logger.info("Failed to start recording: \(error)")
                    recordingOverlay.showError()
                    statusBarController?.updateState(.error)
                }
            }
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

        guard await SpeechPermission.request() else {
            await MainActor.run {
                logger.error("Speech recognition permission denied")
                self.showSpeechPermissionDeniedAlert()
                statusBarController?.updateState(.idle)
            }
            return
        }

        let session = ContinuousDictationSession(idleThreshold: DoubleTapTalkSettings.shared.relayIdleThreshold)
        session.onLiveText = { [weak self] text in
            Task { @MainActor in self?.recordingOverlay.updateLiveText(text) }
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
        relayIsFinalizing = false
        relaySegmentsInserted = 0
        relaySessionChars = 0
        relaySessionStartedAt = Date()

        await MainActor.run {
            // Session HUD: persistent capsule + menu bar header for as long as
            // the microphone stays open.
            recordingOverlay.beginRelaySession(idleThreshold: session.idleThreshold)
            statusBarController?.beginRelaySession()
            statusBarController?.updateState(.recording)
            logger.info("Relay dictation started")
        }
    }

    /// Backspace while a relay session is live: stop AND discard the active
    /// segment, then close the session for real. The user is editing the
    /// document — nothing more may land in it. `relaySession == nil` (no live
    /// session, or a stray Backspace) is filtered out here.
    private func stopRelayViaBackspace() {
        guard let session = relaySession else { return }
        // The Control-tap stop path clears HotkeyService's recording state;
        // this non-Control path must too, or the next Control tap is read as
        // "stopping a recording" that no longer exists.
        hotkeyService?.clearRecording()
        relaySession = nil
        relayIsFinalizing = true
        statusBarController?.markRelayFinalizing()
        Task {
            await session.stopDiscardingActive()
            await MainActor.run { self.completeRelaySession() }
        }
    }

    /// Closes the relay session for real: summary log, capsule receipt, menu
    /// bar reset. Shared by the final-segment injection path (finalize) and the
    /// Backspace discard path — both mean the session is over.
    private func completeRelaySession() {
        let inserted = relaySegmentsInserted
        let chars = relaySessionChars
        let duration = relaySessionStartedAt.map { Date().timeIntervalSince($0) }
        let durationText = duration.map { String(format: "%.1f", $0) } ?? "?"
        logger.info("Relay session complete: \(inserted) segments inserted · \(chars) chars · \(durationText)s")
        recordingOverlay.endRelaySession()
        statusBarController?.endRelaySession()
        relayIsFinalizing = false
        relaySegmentsInserted = 0
        relaySessionChars = 0
        relaySessionStartedAt = nil
    }

    private func stopRecording() {
        statusBarController?.updateState(.processing)
        logger.info("Recording stopped")

        // Captured now: any result produced from here on is only allowed to be
        // injected while this is still the newest dictation.
        let generation = generationSnapshot()

        // The relay engine is the one and only mode: stop() finalizes the
        // whole session; already-rotated segments are inserted in order before
        // the final segment is refined + injected.
        guard let session = relaySession else {
            // A stray stop tap with no live session: nothing to finalize.
            logger.info("Stop tap with no live relay session — ignored")
            statusBarController?.updateState(.idle)
            return
        }
        relaySession = nil
        relayIsFinalizing = true
        statusBarController?.markRelayFinalizing()
        Task {
            // stop() delivers all rotated segments (in order) before it
            // returns, so enqueuing the final one here lands it last.
            let result = await session.stop()
            self.enqueueRelaySegment(result, final: true, generation: generation)
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
    /// polish point feeding it — see AGENTS.md). Reports which app the text
    /// went into, so an injection drifting to the wrong window is traceable.
    private func inject(_ text: String) {
        let target = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        logger.info("Injecting \(text.count) chars into \(target): \(text)")
        textInjectionService?.injectText(text)
        NSSound(named: "Pop")?.play()
    }

    /// Intermediate segment: cloud ASR with Apple fallback, then LLM
    /// refinement (when enabled) using earlier segments as context, then inject
    /// quietly — never touches the overlay or the live segment. Segments with
    /// no words recognized by Apple are skipped (no blank audio to ASR).
    private func insertRelaySegment(_ result: ContinuousDictationSession.SegmentTranscript, generation: Int) async {
        let segmentBegan = Date()
        await MainActor.run { self.recordingOverlay.noteSegmentStarted() }
        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.info("Relay segment: no words recognized by Apple — skipping")
            await MainActor.run { self.recordingOverlay.noteSegmentSkipped() }
            return
        }
        var text = result.text
        let asr = ASRSettings.current()
        var cloudMs = 0
        if asr.enabled, let url = result.recordingFileURL {
            await MainActor.run { self.recordingOverlay.showTranscribing() }
            let cloudBegan = Date()
            if let cloudText = await CloudTranscriptionService.shared.transcribe(fileURL: url, settings: asr) {
                text = cloudText
                logger.info("Relay segment: cloud transcription used")
            } else {
                logger.info("Relay segment: cloud unavailable — using Apple result")
            }
            cloudMs = Int(Date().timeIntervalSince(cloudBegan) * 1000)
        }

        // Refinement runs when the LLM is enabled+configured — automatically,
        // no tap distinction needed.
        var polishMs = 0
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await MainActor.run { self.recordingOverlay.showPolishing() }
            let polishBegan = Date()
            text = await PolishProcessor().process(
                rawText: text,
                settings: LLMSettings.current(),
                previousSegments: segmentHistorySnapshot()
            )
            polishMs = Int(Date().timeIntervalSince(polishBegan) * 1000)
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Recognized but never inserted: the session HUD must say so, or the
            // user assumes their words are in the document.
            logger.info("Relay segment: nothing left to insert — reporting as failed")
            await MainActor.run { self.recordingOverlay.noteSegmentFailed() }
            return
        }
        guard isCurrentGeneration(generation) else {
            logger.info("Relay segment finished after session \(generation) ended — dropping")
            return
        }
        appendSegmentHistory(text)
        let toInject = text
        let characterCount = text.count
        let totalMs = Int(Date().timeIntervalSince(segmentBegan) * 1000)
        let cloudMsFinal = cloudMs
        let polishMsFinal = polishMs
        await MainActor.run {
            guard self.isCurrentGeneration(generation) else { return }
            // Receipt: the user hears the pop, and now sees which segment landed.
            self.relaySegmentsInserted += 1
            self.relaySessionChars += characterCount
            self.recordingOverlay.noteSegmentInserted(characters: characterCount)
            self.statusBarController?.updateRelayProgress(segments: self.relaySegmentsInserted)
            self.inject(toInject)
            self.logger.info("Relay segment \(self.relaySegmentsInserted) injected in \(totalMs)ms (cloud \(cloudMsFinal)ms · polish \(polishMsFinal)ms · \(characterCount) chars)")
        }
    }

    /// Final segment: cloud ASR (fallback Apple) then the classic refine →
    /// reveal → inject → dismiss flow, with earlier segments as context. No
    /// upload when Apple recognized no words.
    private func finishRelay(finalResult: ContinuousDictationSession.SegmentTranscript, generation: Int) async {
        await MainActor.run { self.recordingOverlay.noteSegmentStarted() }
        var rawText = finalResult.text
        let asr = ASRSettings.current()
        let hasWords = !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if asr.enabled, hasWords, let url = finalResult.recordingFileURL {
            await MainActor.run {
                guard self.isCurrentGeneration(generation) else { return }
                self.recordingOverlay.showTranscribing()
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
                self.recordingOverlay.showPolishing()
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
        
        // "what changed" moment: when the polish pass actually changed the text,
        // hold the result in the overlay for a beat so the user sees the edit
        // before it lands. The capsule's success styling carries the ✨ now.
        let wasChanged = !text.isEmpty && text != rawText
        
        await MainActor.run {
            guard self.isCurrentGeneration(generation) else { return }
            if text.isEmpty {
                self.recordingOverlay.showEmpty()
            } else if wasChanged {
                self.recordingOverlay.showResult(text)
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
            if self.relayIsFinalizing {
                if !text.isEmpty {
                    self.relaySegmentsInserted += 1
                    self.relaySessionChars += text.count
                    self.recordingOverlay.noteFinalSegmentInserted(characters: text.count)
                }
                // A relay session closes with a receipt: how much landed, how
                // long it took, what never made it in. Stopping a long session
                // must not look like a plain dictation.
                self.completeRelaySession()
            } else {
                self.recordingOverlay.dismiss()
            }
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