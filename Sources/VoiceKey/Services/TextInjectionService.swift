import Foundation
import AppKit
import CoreGraphics
import Carbon

final class TextInjectionService {
    private let logger = FileLogger.shared
    
    func injectText(_ text: String) {
        logger.info("Injecting \(text.count) characters...")
        logger.debug("Text preview: \(text.prefix(50))\(text.count > 50 ? "..." : "")")
        
        // First try direct CGEvent injection
        if !injectDirect(text) {
            logger.warning("Direct injection failed, trying pasteboard method")
            // Fallback to pasteboard method
            injectViaPasteboard(text)
        } else {
            logger.info("Direct injection successful")
        }
    }
    
    private func injectDirect(_ text: String) -> Bool {
        // Get the frontmost application
        guard let targetApp = NSWorkspace.shared.frontmostApplication else {
            logger.warning("No frontmost application found")
            return false
        }
        
        let appName = targetApp.localizedName ?? "Unknown"
        logger.debug("Target application: \(appName) (PID: \(targetApp.processIdentifier))")
        
        // Don't inject into VoiceKey itself
        if appName.lowercased().contains("voicekey") {
            logger.warning("Refusing to inject into VoiceKey itself")
            return false
        }
        
        logger.info("Injecting text into: \(appName)")
        
        // Convert string to key events
        let source = CGEventSource(stateID: .hidSystemState)
        
        for char in text {
            guard char.unicodeScalars.first != nil else { continue }
            
            // Create key down event
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
                continue
            }
            
            // Set Unicode character
            var utf16 = Array(String(char).utf16)
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            
            // Create key up event
            guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            
            // Post events at HID level (higher priority)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            
            // Small delay between characters
            usleep(500) // 0.5ms
        }
        
        logger.debug("Injected \(text.count) characters via direct method")
        return true
    }
    
    private func injectViaPasteboard(_ text: String) {
        logger.info("Using pasteboard injection method")
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        logger.debug("Previous pasteboard contents: \(previousContents?.prefix(30) ?? "nil")")
        
        // Set new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        logger.debug("Text copied to pasteboard")
        
        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Key code for V is 9
        let vKeyCode: CGKeyCode = 9
        
        // Cmd down
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true) else {
            logger.error("Failed to create Cmd key down event")
            return
        }
        cmdDown.flags = .maskCommand
        cmdDown.post(tap: .cghidEventTap)
        
        // V down
        guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            logger.error("Failed to create V key down event")
            return
        }
        vDown.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)
        
        // V up
        guard let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            logger.error("Failed to create V key up event")
            return
        }
        vUp.flags = .maskCommand
        vUp.post(tap: .cghidEventTap)
        
        // Cmd up
        guard let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false) else {
            logger.error("Failed to create Cmd key up event")
            return
        }
        cmdUp.post(tap: .cghidEventTap)
        
        logger.info("Pasteboard injection completed")
        
        // Restore pasteboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
                self.logger.debug("Pasteboard restored")
            }
        }
    }
}