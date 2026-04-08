import Foundation
import AVFoundation

final class AudioRecorder {
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    
    private let sampleRate: Double = 16000
    private let channels: Int = 1
    private let logger = FileLogger.shared
    
    init() {
        logger.debug("AudioRecorder initialized (sampleRate: \(sampleRate)Hz, channels: \(channels))")
        // No AVAudioSession needed on macOS
    }
    
    func startRecording() throws {
        logger.info("Starting audio recording...")
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "doubletaptalk_recording_\(UUID().uuidString).wav"
        recordingURL = tempDir.appendingPathComponent(fileName)
        logger.debug("Recording URL: \(recordingURL?.path ?? "unknown")")
        
        guard let url = recordingURL else {
            logger.error("Failed to create recording URL")
            throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create recording URL"])
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        logger.debug("Audio settings: \(sampleRate)Hz, \(channels)ch, 16-bit PCM")
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.prepareToRecord()
            logger.debug("AVAudioRecorder prepared")
        } catch {
            logger.error("Failed to create AVAudioRecorder: \(error)")
            throw error
        }
        
        guard audioRecorder?.record() == true else {
            logger.error("Failed to start recording")
            throw NSError(domain: "AudioRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to start recording"])
        }
        
        logger.info("Recording started successfully")
    }
    
    func stopRecording() -> URL? {
        logger.info("Stopping audio recording...")
        
        let duration = audioRecorder?.currentTime ?? 0
        logger.debug("Recording duration: \(String(format: "%.2f", duration))s")
        
        audioRecorder?.stop()
        audioRecorder = nil
        
        let url = recordingURL
        if let url = url {
            logger.debug("Recording saved to: \(url.path)")
            
            // Log file size
            if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int {
                logger.debug("Recording file size: \(fileSize) bytes")
            }
        } else {
            logger.warning("Recording URL is nil")
        }
        recordingURL = nil
        
        logger.info("Recording stopped")
        return url
    }
    
    var isRecording: Bool {
        return audioRecorder?.isRecording ?? false
    }
}