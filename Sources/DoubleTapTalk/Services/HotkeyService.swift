import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

final class HotkeyService {
    var onHotkeyPressed: (() -> Void)?
    /// Fired on the first Control tap release while recording.
    /// Refinement is governed by settings (every segment refines when enabled),
    /// so there is no longer a no-refinement stop option.
    var onHotkeyReleased: (() -> Void)?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRecording = false
    private var isTapActive = false
    private var healthCheckTimer: Timer?
    private let logger = FileLogger.shared
    
    // Track tap timing for double-tap detection
    private var lastTapTime: Date? = nil
    private let doubleTapThreshold: TimeInterval = 0.3 // 300ms max between taps
    
    func start() {
        guard !isTapActive else { return }
        logger.info("Starting hotkey service (double-tap Control detection)...")
        
        // Check accessibility permissions first
        if !AXIsProcessTrusted() {
            logger.error("Accessibility permissions NOT granted!")
            logger.error("Please open System Settings → Privacy & Security → Accessibility")
            logger.error("Then add DoubleTapTalk to the allowed applications list")
            showPermissionsAlert()
            pollForAccessibility()
            return
        }
        
        logger.debug("Accessibility permissions verified")
        
        // Try creating the tap with multiple approaches
        guard createEventTap() else {
            logger.error("Failed to create event tap even with permissions")
            logger.error("Try: Quit DoubleTapTalk → Reopen → Check Accessibility permissions again")
            return
        }
        
        logger.info("Hotkey service started successfully - double-tap Control to record")
        
        // Start health check timer
        startHealthCheck()
    }
    
    /// Self-heal: keeps checking every 2s until Accessibility is granted, then
    /// starts the event tap — no manual restart needed after granting permission.
    private func pollForAccessibility() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, !self.isTapActive else { return }
            if AXIsProcessTrusted() {
                logger.info("Accessibility granted — starting hotkey service now")
                DispatchQueue.main.async { self.start() }
            } else {
                self.pollForAccessibility()
            }
        }
    }
    
    /// Menu-driven stop ("End Continuous Dictation"). Mirrors a Control tap
    /// release exactly, including the internal flag and the pending
    /// double-tap window, so the next tap is read as a fresh start instead of a
    /// second stop.
    func requestStop() {
        guard isRecording else {
            logger.debug("Stop requested but no session is running — ignored")
            return
        }
        isRecording = false
        lastTapTime = nil
        logger.info("Stop requested from the menu")
        DispatchQueue.main.async { [weak self] in
            self?.onHotkeyReleased?()
        }
    }

    func stop() {
        logger.info("Stopping hotkey service...")
        // Stop health check
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            logger.debug("Event tap disabled")
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            logger.debug("Run loop source removed")
        }
        // Remove tap invalidation listener (so teardown can't re-enter us),
        // then invalidate.
        if let tap = eventTap {
            CFMachPortSetInvalidationCallBack(tap, nil)
            CFMachPortInvalidate(tap)
            logger.debug("Event tap invalidated")
        }
        eventTap = nil
        runLoopSource = nil
        isTapActive = false
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
        
        if isRecording {
            // While recording, the first tap stops immediately (no double-tap
            // wait — refinement no longer depends on tap count).
            logger.info("Control tap while recording — stopping")
            isRecording = false
            lastTapTime = nil
            DispatchQueue.main.async {
                self.onHotkeyReleased?()
            }
        } else {
            // Not recording - handle start
            if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) < doubleTapThreshold {
                // Double tap detected while not recording: start recording
                logger.info("Double-tap Control detected - start recording")
                lastTapTime = nil
                isRecording = true
                DispatchQueue.main.async {
                    self.onHotkeyPressed?()
                }
            } else {
                // First tap while not recording: wait for possible second tap
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
                
                // Add tap invalidation handler to detect when tap is killed by system.
                // NOTE: CFMachPortSetInvalidationCallBack delivers no user info, so the
                // callback's second parameter must NOT be treated as our service pointer
                // (doing that dereferenced garbage and crashed on quit). Recovery is
                // handled by the health-check timer.
                CFMachPortSetInvalidationCallBack(tap, { _, _ in
                    FileLogger.shared.error("Event tap was invalidated by the system")
                })
                
                CGEvent.tapEnable(tap: tap, enable: true)
                isTapActive = true
                logger.debug("Event tap enabled and active")
                return true
            }
        }
        
        return false
    }
    
    private func startHealthCheck() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !self.isTapActive {
                self.logger.error("Event tap inactive, attempting recovery")
                DispatchQueue.main.async { self.start() }
            }
        }
        RunLoop.current.add(healthCheckTimer!, forMode: .common)
    }
    
    private func showPermissionsAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "DoubleTapTalk needs accessibility permission to detect hotkeys.\n\nClick 'Open Privacy Settings' to enable it."
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
