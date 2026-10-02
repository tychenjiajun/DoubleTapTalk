import Foundation
import AppKit
import CoreGraphics
import Carbon

final class TextInjectionService {
    private let logger = FileLogger.shared
    /// Clipboard content to put back after a pasteboard-based injection,
    /// captured only while no restore is pending — back-to-back relay
    /// segments must restore the user's original clipboard, not each
    /// other's text.
    private var clipboardBeforeInjection: String?
    private var clipboardRestorePending = false
    /// Bumped per pasteboard injection: a scheduled restore only runs while
    /// it still owns the clipboard (a newer segment may have claimed it).
    private var pasteboardEpoch = 0

    func injectText(_ text: String) {
        logger.info("Injecting \(text.count) characters...")
        logger.debug("Text preview: \(text.prefix(50))\(text.count > 50 ? "..." : "")")

        // Never target ourselves — the "refuse" check used to live inside
        // injectDirect, where it returned false and fell through to the
        // pasteboard path, which would happily paste into DoubleTapTalk.
        if let front = NSWorkspace.shared.frontmostApplication,
           (front.localizedName ?? "").lowercased().contains("doubletaptalk") {
            logger.warning("Refusing to inject into DoubleTapTalk itself")
            return
        }

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
        logger.info("Injecting text into: \(appName)")

        // Convert string to key events
        let source = CGEventSource(stateID: .hidSystemState)
        var posted = 0

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
            posted += 1

            // Small delay between characters
            usleep(500) // 0.5ms
        }

        if posted == 0 && !text.isEmpty {
            // Not a single event could be posted (no event source / missing
            // permission): report failure so the pasteboard fallback runs —
            // this used to return true unconditionally, silently skipping it.
            logger.warning("Direct injection posted 0 events for \(text.count) chars")
            return false
        }
        logger.debug("Injected \(posted)/\(text.count) chars via direct method")
        return true
    }

    private func injectViaPasteboard(_ text: String) {
        logger.info("Using pasteboard injection method")
        let pasteboard = NSPasteboard.general

        // Capture the ORIGINAL clipboard only when no restore is pending:
        // segment N+1 arriving before segment N's restore must not make
        // segment N's text the "original" we eventually put back.
        if !clipboardRestorePending {
            clipboardBeforeInjection = pasteboard.string(forType: .string)
            clipboardRestorePending = true
        }
        pasteboardEpoch += 1
        let epoch = pasteboardEpoch
        logger.debug("Previous pasteboard contents: \((clipboardBeforeInjection ?? "nil").prefix(30))")

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

        // Restore the clipboard after the paste has been consumed. Guards:
        //  - a newer injection owns the clipboard now (epoch) — its restore
        //    will handle the cleanup, so this one must not wipe its text;
        //  - the clipboard no longer holds our text (the user copied
        //    something new in the meantime) — leave it alone;
        //  - only this injection's captured "original" is written back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.pasteboardEpoch == epoch else { return }
            self.clipboardRestorePending = false
            let restoreTo = self.clipboardBeforeInjection
            self.clipboardBeforeInjection = nil
            guard pasteboard.string(forType: .string) == text else {
                self.logger.debug("Clipboard changed since injection — leaving it alone")
                return
            }
            self.logger.debug("Restoring clipboard")
            pasteboard.clearContents()
            if let restoreTo {
                pasteboard.setString(restoreTo, forType: .string)
            }
        }
    }
}
