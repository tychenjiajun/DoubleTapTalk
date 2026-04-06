import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

final class HotkeyService {
    var onHotkeyPressed: (() -> Void)?
    var onHotkeyReleased: (() -> Void)?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRecording = false
    private let logger = FileLogger.shared
    
    // Track tap timing for double-tap detection
    private var lastTapTime: Date? = nil
    private let doubleTapThreshold: TimeInterval = 0.3 // 300ms max between taps
    
    func start() {
        logger.info("Starting hotkey service (double-tap Control detection)...")
        
        // Check accessibility permissions first
        if !AXIsProcessTrusted() {
            logger.error("Accessibility permissions NOT granted!")
            logger.error("Please open System Settings → Privacy & Security → Accessibility")
            logger.error("Then add VoiceKey to the allowed applications list")
            showPermissionsAlert()
            return
        }
        
        logger.debug("Accessibility permissions verified")
        
        // Try creating the tap with multiple approaches
        guard createEventTap() else {
            logger.error("Failed to create event tap even with permissions")
            logger.error("Try: Quit VoiceKey → Reopen → Check Accessibility permissions again")
            return
        }
        
        logger.info("Hotkey service started successfully - double-tap Control to record")
    }
    
    func stop() {
        logger.info("Stopping hotkey service...")
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            logger.debug("Event tap disabled")
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            logger.debug("Run loop source removed")
        }
        eventTap = nil
        runLoopSource = nil
        logger.info("Hotkey service stopped")
    }
    
    private func handleFlagsChangedEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged else {
            return Unmanaged.passRetained(event)
        }
        
        let flags = event.flags
        
        // Get the key code from the event to help identify which specific key
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // For Control keys, we need to infer left vs right
        // Key code 0x3B (59) is Left Control, 0x3E (62) is Right Control
        let isControl = keyCode == 59 || keyCode == 62
        
        if isControl {
            let controlDown = flags.contains(.maskControl)
            logger.debug("Control key event - keyCode: \(keyCode), down: \(controlDown)")
            
            // Only detect taps when releasing the key
            if !controlDown {
                handleControlTap()
            }
        }
        
        return Unmanaged.passRetained(event)
    }
    
    private func handleControlTap() {
        let now = Date()
        
        // Check if this is a double tap
        if let lastTap = lastTapTime,
           now.timeIntervalSince(lastTap) < doubleTapThreshold {
            // Double tap detected - toggle recording
            logger.info("Double-tap Control detected!")
            toggleRecording()
            lastTapTime = nil
        } else {
            // First tap - wait for potential second tap
            logger.debug("First Control tap detected, waiting for second...")
            lastTapTime = now
            
            // After threshold, reset (single tap ignored)
            DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapThreshold) {
                if self.lastTapTime != nil {
                    self.logger.debug("Single tap timeout - ignored")
                }
                self.lastTapTime = nil
            }
        }
    }
    
    private func createEventTap() -> Bool {
        let eventMask = (1 << CGEventType.flagsChanged.rawValue)
        
        // Try multiple tap configurations
        let configs: [(tap: CGEventTapLocation, place: CGEventTapPlacement, options: CGEventTapOptions)] = [
            (.cgSessionEventTap, .headInsertEventTap, .defaultTap),
            (.cghidEventTap, .tailAppendEventTap, .listenOnly),
        ]
        
        for config in configs {
            if let tap = CGEvent.tapCreate(
                tap: config.tap,
                place: config.place,
                options: config.options,
                eventsOfInterest: CGEventMask(eventMask),
                callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                    guard let refcon = refcon else {
                        return Unmanaged.passRetained(event)
                    }
                    let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
                    return service.handleFlagsChangedEvent(proxy: proxy, type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) {
                eventTap = tap
                logger.debug("Event tap created with config: \(config.tap.rawValue)")
                
                runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
                CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                return true
            }
        }
        
        return false
    }
    
    private func toggleRecording() {
        isRecording.toggle()
        let action = isRecording ? "START" : "STOP"
        logger.info("Toggle recording: \(action)")
        DispatchQueue.main.async {
            if self.isRecording {
                self.logger.debug("Calling onHotkeyPressed callback")
                self.onHotkeyPressed?()
            } else {
                self.logger.debug("Calling onHotkeyReleased callback")
                self.onHotkeyReleased?()
            }
        }
    }
    
    private func showPermissionsAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "VoiceKey needs accessibility permission to detect hotkeys.\n\nClick 'Open Privacy Settings' to enable it."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Privacy Settings")
            alert.addButton(withTitle: "OK")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }
}