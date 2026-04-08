import Foundation
import AppKit
import CoreGraphics
import Carbon

final class TextInjectionService {
    private let logger = FileLogger.shared
    
    func injectText(_ text: String) {
        logger.info("Injecting \(text.count) characters...")
        logger.debug("Text preview: \(text.prefix(50))\(text.count > 50 ? "..." : "")")
        
        // Try direct CGEvent injection first
        if !injectDirect(text) {
            logger.warning("Direct injection failed, using pasteboard method as fallback")
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
        
        // Don't inject into DoubleTapTalk itself
        if appName.lowercased().contains("doubletaptalk") {
            logger.warning("Refusing to inject into DoubleTapTalk itself")
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
        
        // Ensure focus on text field with small delay
        Thread.sleep(forTimeInterval: 0.1)
        
        // Set new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        logger.debug("Text copied to pasteboard")
        
        // Small delay before simulating Cmd+V
        Thread.sleep(forTimeInterval: 0.05)
        
        // Simulate Cmd+V with proper event sequence
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Key code for V is 9
        let vKeyCode: CGKeyCode = 9
        
        // Down both Command and V together
        guard let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            logger.error("Failed to create Cmd+V down event")
            return
        }
        cmdVDown.flags = [.maskCommand]
        cmdVDown.post(tap: .cghidEventTap)
        
        // Up both Command and V together  
        guard let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            logger.error("Failed to create Cmd+V up event")
            return
        }
        cmdVUp.flags = [.maskCommand]
        cmdVUp.post(tap: .cghidEventTap)
        
        logger.info("Pasteboard injection completed")
        
        // Restore pasteboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.logger.debug("Restoring pasteboard")
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            } else {
                pasteboard.clearContents()
            }
        }
    }
}