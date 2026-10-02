import Foundation
import AVFoundation
import CoreAudio

/// Service for checking and requesting microphone permission
final class MicrophonePermissionService {
    static let shared = MicrophonePermissionService()
    private let logger = FileLogger.shared
    
    private init() {}
    
    /// Check if microphone permission is granted
    func hasMicrophonePermission() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined, .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    /// Request microphone permission (shows system prompt)
    /// - Returns: true if permission was granted, false otherwise
    /// - Note: This is async and will show a system dialog if permission is notDetermined
    func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            logger.debug("Microphone permission already granted")
            return true
            
        case .notDetermined:
            logger.info("Requesting microphone permission...")
            let logger = self.logger
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    if granted {
                        logger.info("Microphone permission granted")
                    } else {
                        logger.warning("Microphone permission denied")
                    }
                    continuation.resume(returning: granted)
                }
            }
            
        case .denied:
            logger.error("Microphone permission was denied. User must grant in System Settings > Privacy & Security > Microphone")
            return false
            
        case .restricted:
            logger.error("Microphone access is restricted (parental controls or MDM)")
            return false
            
        @unknown default:
            logger.error("Unknown microphone permission status")
            return false
        }
    }
    
    /// Get the currently selected microphone device name using CoreAudio
    func currentMicrophoneName() -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &size,
            &deviceID
        )
        
        guard status == noErr, deviceID != 0 else { return nil }
        
        // Get device name
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        
        let nameStatus = AudioObjectGetPropertyData(
            deviceID,
            &nameAddress,
            0,
            nil,
            &nameSize,
            &name
        )
        
        guard nameStatus == noErr, let name else { return nil }
        // Get-property: the system owns the string — don't over-retain it.
        return name.takeUnretainedValue() as String
    }
    
    /// Get human-readable description of current permission status
    func permissionStatusDescription() -> String {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return "Microphone permission granted"
        case .notDetermined:
            return "Microphone permission not requested yet"
        case .denied:
            return "Microphone permission denied - grant in System Settings > Privacy & Security > Microphone"
        case .restricted:
            return "Microphone access restricted"
        @unknown default:
            return "Unknown microphone permission status"
        }
    }
}
