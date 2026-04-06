import Foundation
import CoreGraphics
import AppKit

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
        
        // First try to create a tap for modifier keys
        let eventMask = (1 << CGEventType.flagsChanged.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
                return service.handleFlagsChangedEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("Failed to create event tap. Please grant accessibility permissions in System Settings > Privacy & Security > Accessibility")
            return
        }
        
        eventTap = tap
        logger.debug("Event tap created successfully")
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Hotkey service started - listening for double-tap Control")
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
}