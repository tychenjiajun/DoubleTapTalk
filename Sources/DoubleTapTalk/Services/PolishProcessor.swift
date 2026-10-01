import Foundation
import AppKit

private let logger = FileLogger.shared

/// Shared polish pipeline used by BOTH the file-based ASR path and the
/// streaming Apple path. Extracted from ASRService so there is exactly
/// one place that performs LLM polishing (DRY).
///
/// Guarantees: never throws for LLM failures — polishing is best-effort and
/// always falls back to the original text.
final class PolishProcessor {

    /// Applies LLM polishing to raw speech-to-text output when enabled and configured.
    /// - Returns: the polished text, or the original text unchanged when polishing is
    ///   disabled, unconfigured, or fails.
    func process(rawText: String, settings: LLMSettings, polishEnabled: Bool) async -> String {
        guard polishEnabled, settings.enabled else {
            return rawText
        }

        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return rawText
        }

        guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
            logger.warning("LLM polishing enabled but no API key configured")
            return rawText
        }

        logger.info("Applying LLM polishing...")

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
            focusedElementInfo = AccessibilityService.shared.captureFocusedElementInfo(from: targetApp)
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
            let polishedText = try await withTimeout(settings.timeout) {
                try await LLMService.shared.polish(text: rawText, settings: settings, context: polishContext)
            }
            logger.info("✓ Polished successfully: '\(polishedText.prefix(100))\(polishedText.count > 100 ? "..." : "")'")

            // Compare original vs polished
            if polishedText == rawText {
                logger.info("→ No changes made (original and polished text are identical)")
            } else {
                logger.debug("→ Original length: \(rawText.count) chars → Polished length: \(polishedText.count) chars")
            }

            return polishedText
        } catch {
            logger.error("LLM polishing failed: \(error). Using original text.")
            // Continue with original text
            return rawText
        }
    }

    private func withTimeout<T>(_ seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ASRError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}