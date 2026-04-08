import Foundation
import AppKit

final class ASRService {
    private var currentBackend: ASRBackend?
    private let logger = FileLogger.shared
    
    init() {
        updateBackend()
    }
    
    func updateBackend() {
        let settings = DoubleTapTalkSettings.shared
        
        switch settings.backendType {
        case .openAI:
            currentBackend = OpenAIWhisperBackend(apiKey: settings.apiKey, apiURL: settings.apiURL)
        case .groq:
            currentBackend = GroqBackend(apiKey: settings.apiKey, apiURL: settings.apiURL)
        case .dashscope:
            currentBackend = DashscopeASRBackend(apiKey: settings.apiKey, apiURL: settings.apiURL)
        case .local:
            currentBackend = LocalWhisperBackend(apiURL: settings.apiURL)
        }
    }
    
    func transcribe(audioURL: URL, polish: Bool) async throws -> String? {
        // Update backend in case settings changed
        updateBackend()
        
        guard let backend = currentBackend else {
            logger.log("No backend configured")
            throw ASRError.invalidURL
        }
        
        logger.log("Using backend: \(backend.name)")
        
        let settings = DoubleTapTalkSettings.shared
        logger.log("API Key exists: \(settings.apiKey != nil ? "yes" : "no")")
        logger.log("Transcribing with model: \(settings.model), language: \(settings.language)")
        logger.log("LLM Polishing: \(settings.llmEnabled ? "enabled (\(settings.llmProvider.displayName))" : "disabled")")
        
        do {
            let result = try await backend.transcribe(
                audioURL: audioURL,
                language: settings.language == "auto" ? nil : settings.language,
                model: settings.model
            )
            
            var text = result.text
            logger.log("Got transcription: '\(text)'")
            
            // Apply LLM polishing if requested and enabled
            if polish && settings.llmEnabled && !text.isEmpty {
                logger.info("Applying LLM polishing...")
                
                // Build LLMSettings from global settings
                let llmSettings = LLMSettings(
                    enabled: true,
                    provider: settings.llmProvider,
                    apiKey: settings.llmAPIKey,
                    model: settings.llmModel,
                    temperature: settings.llmTemperature,
                    systemPrompt: settings.llmSystemPrompt,
                    baseURL: settings.llmBaseURL,
                    timeout: settings.llmTimeout,
                    pinnedProfile: settings.pinnedPolishProfile,
                    useAppSpecificPolish: settings.useAppSpecificPolish
                )
                
                // Get user locale with region for better localization
                let localeIdentifier = Locale.current.identifier  // e.g., "en_US", "zh_CN"
                
                // Capture context before calling LLM service
                let targetApp = NSWorkspace.shared.frontmostApplication ?? NSRunningApplication.current
                
                // Get existing text and focused element info via Accessibility API (if permission granted)
                var existingText: String?
                var conversationHint: String?
                var focusedElementInfo: FocusedElementInfo?
                
                if AccessibilityService.shared.hasAccessibilityPermission() {
                    // Capture focused element info once and reuse
                    focusedElementInfo = AccessibilityService.shared.captureFocusedElementInfoDetailed(from: targetApp)
                    existingText = focusedElementInfo?.value
                    
                    // For terminals, also get screen buffer as conversation hint
                    let tempContext = AppContext(app: targetApp, focusedElementInfo: focusedElementInfo)
                    if tempContext.isTerminal {
                        conversationHint = AccessibilityService.shared.getTerminalContext(from: targetApp)
                    }
                } else {
                    logger.warning("Accessibility permission not granted — context reading disabled")
                }
                
                let appContext = AppContext(
                    app: targetApp,
                    focusedElementInfo: focusedElementInfo
                )
                
                let polishContext = PolishContext(
                    targetApp: appContext,
                    existingText: existingText,
                    conversationHint: conversationHint,
                    userLocale: localeIdentifier
                )
                
                logger.debug("Polish context:")
                logger.debug("  - Target app: \(polishContext.targetApp.appName)")
                logger.debug("  - Bundle ID: \(polishContext.targetApp.bundleID ?? "unknown")")
                logger.debug("  - Is terminal: \(polishContext.targetApp.isTerminal)")
                logger.debug("  - Existing text length: \((polishContext.existingText?.count ?? 0)) chars")
                logger.debug("  - Terminal context length: \((polishContext.conversationHint?.count ?? 0)) chars")
                
                do {
                    // Try polishing with configurable timeout
                    let polishedText = try await withTimeout(settings.llmTimeout) {
                        try await LLMService.shared.polish(text: text, settings: llmSettings, context: polishContext)
                    }
                    logger.info("✓ Polished successfully: '\(polishedText.prefix(100))\(polishedText.count > 100 ? "..." : "")'")
                    
                    // Compare original vs polished
                    if polishedText == text {
                        logger.info("→ No changes made (original and polished text are identical)")
                    } else {
                        logger.debug("→ Original length: \(text.count) chars → Polished length: \(polishedText.count) chars")
                    }
                    
                    text = polishedText
                } catch {
                    logger.error("LLM polishing failed: \(error). Using original text.")
                    // Continue with original text
                }
            }
            
            return text
        } catch {
            logger.log("Transcription error: \(error)")
            throw error
        }
    }
    
    private func withTimeout<T>(_ seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        let task = Task {
            try await operation()
        }
        _ = Task {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            task.cancel()
            throw ASRError.timeout
        }
        return try await task.value
    }
}