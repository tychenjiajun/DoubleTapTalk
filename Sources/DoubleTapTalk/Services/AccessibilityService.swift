import Foundation
import AppKit

/// Service for reading text content from applications via macOS Accessibility API
final class AccessibilityService {
    static let shared = AccessibilityService()
    private let logger = FileLogger.shared
    
    /// Check if Accessibility permission is granted
    func hasAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /// Request Accessibility permission (shows system prompt)
    func requestAccessibilityPermission() {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Get existing text from the focused UI element of an application
    /// - Parameter app: The target application
    /// - Returns: Text in the focused field, or nil if unavailable
    func getExistingText(from app: NSRunningApplication) -> String? {
        let pid = app.processIdentifier
        
        let axApp = AXUIElementCreateApplication(pid)
        
        // Get focused element
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { 
            logger.debug("Could not get focused element from \(app.localizedName ?? "unknown app")")
            return nil 
        }
        
        // CFTypeRef → AXUIElement: Swift treats the conditional downcast as an
        // unconditional coercion (it won't even compile), so verify the
        // dynamic type ourselves before trusting it.
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            logger.debug("Focused element is not an AXUIElement")
            return nil
        }
        let element = focused as! AXUIElement
        
        // Try kAXValueAttribute first (text fields, text areas)
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let value = valueRef as? String, !value.isEmpty {
            logger.debug("Got existing text via kAXValueAttribute (\(value.count) chars)")
            return value
        }
        
        // Fallback: kAXSelectedTextAttribute (gets selected/highlighted text)
        var selectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
           let selected = selectedRef as? String, !selected.isEmpty {
            logger.debug("Got existing text via kAXSelectedTextAttribute (\(selected.count) chars)")
            return selected
        }
        
        // Try kAXTitleAttribute as another fallback (for some apps)
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let title = titleRef as? String, !title.isEmpty {
            logger.debug("Got existing text via kAXTitleAttribute (\(title.count) chars)")
            return title
        }
        
        logger.debug("No existing text available from focused element")
        return nil
    }
    
    /// Get terminal context (last N lines of screen buffer)
    /// - Parameter app: The terminal application
    /// - Returns: Last 15 lines of terminal output, or nil if unavailable
    func getTerminalContext(from app: NSRunningApplication) -> String? {
        let pid = app.processIdentifier
        
        let axApp = AXUIElementCreateApplication(pid)
        
        // Get the focused window
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else {
            logger.debug("Could not get focused window from terminal")
            return nil
        }
        
        // Walk the AX tree to find the terminal text content
        guard CFGetTypeID(window) == AXUIElementGetTypeID() else {
            logger.debug("Focused window is not an AXUIElement")
            return nil
        }
        let windowElement = window as! AXUIElement
        guard let fullBuffer = findTerminalTextArea(in: windowElement) else {
            logger.debug("Could not find terminal text area")
            return nil
        }
        
        // Return only the last N lines — enough for context, not too much for the LLM
        let lines = fullBuffer.components(separatedBy: "\n")
        let lastLines = lines.suffix(15).joined(separator: "\n")
        
        logger.debug("Got terminal context (\(lastLines.count) chars, \(lines.suffix(15).count) lines)")
        return lastLines.isEmpty ? nil : lastLines
    }
    
    /// Recursively searches the tree for the terminal's text content.
    ///
    /// Two passes, in order:
    /// 1. the first non-empty `kAXValue` (the actual scrollback / textarea),
    /// 2. only if none exists, `kAXDescription`/`kAXTitle`.
    ///
    /// The window itself is never matched: a terminal window always has a
    /// title ("zsh — 80×24"), so probing it first used to return the title
    /// and never recurse into the buffer at all. The walk is bounded (depth
    /// and node budget) so a huge UI tree can't stall the polish pass.
    private func findTerminalTextArea(in root: AXUIElement) -> String? {
        if let value = firstText(in: root, matching: .value) { return value }
        return firstText(in: root, matching: .descriptionOrTitle)
    }

    private enum TextAttribute { case value, descriptionOrTitle }

    private func firstText(in root: AXUIElement, matching kind: TextAttribute) -> String? {
        let maxDepth = 30
        let maxNodes = 500
        var visited = 0

        func walk(_ element: AXUIElement, isRoot: Bool, depth: Int) -> String? {
            visited += 1
            guard depth <= maxDepth, visited <= maxNodes else { return nil }
            if !isRoot {
                switch kind {
                case .value:
                    if let text = element.copyAttributeValue(kAXValueAttribute as CFString) as? String, !text.isEmpty {
                        return text
                    }
                case .descriptionOrTitle:
                    if let text = element.copyAttributeValue(kAXDescriptionAttribute as CFString) as? String, !text.isEmpty {
                        return text
                    }
                    if let text = element.copyAttributeValue(kAXTitleAttribute as CFString) as? String, !text.isEmpty {
                        return text
                    }
                }
            }
            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let children = childrenRef as? [AXUIElement] else { return nil }
            for child in children {
                if let found = walk(child, isRoot: false, depth: depth + 1) { return found }
            }
            return nil
        }

        return walk(root, isRoot: true, depth: 0)
    }
    
    /// Capture context from an application's focused element
    func captureFocusedElementInfo(from app: NSRunningApplication) -> FocusedElementInfo? {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return nil }
        
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        
        // Get role
        var roleRef: CFTypeRef?
        let role: String
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let r = roleRef as? String {
            role = r
        } else {
            role = "Unknown"
        }
        
        // Get value - try kAXValueAttribute, then kAXSelectedTextAttribute
        var value: String?
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let v = valueRef as? String, !v.isEmpty {
            value = v
        } else {
            var selectedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
               let selected = selectedRef as? String, !selected.isEmpty {
                value = selected
            }
        }
        
        return FocusedElementInfo(role: role, value: value)
    }
}

// MARK: - Convenience Extensions

extension AXUIElement {
    /// Helper to safely get attribute values
    func copyAttributeValue(_ attribute: CFString) -> CFTypeRef? {
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(self, attribute, &ref)
        return result == .success ? ref : nil
    }
}
