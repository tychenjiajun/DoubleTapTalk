import Foundation
import AVFoundation

final class AudioRecorder: NSObject {
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meteringTimer: Timer?
    
    private let sampleRate: Double = 16000
    private let channels: Int = 1
    private let logger = FileLogger.shared
    
    /// Delivers normalized (0...1) audio level while recording, ~30Hz.
    /// Used to drive the recording overlay waveform (DRY across modes).
    var onLevelUpdate: ((Float) -> Void)?
    
    override init() {
        super.init()
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
            audioRecorder?.isMeteringEnabled = true
            logger.debug("AVAudioRecorder prepared")
        } catch {
            logger.error("Failed to create AVAudioRecorder: \(error)")
            throw error
        }
        
        guard audioRecorder?.record() == true else {
            logger.error("Failed to start recording")
            throw NSError(domain: "AudioRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to start recording"])
        }
        
        startMeteringTimer()
        logger.info("Recording started successfully")
    }
    
    func stopRecording() -> URL? {
        logger.info("Stopping audio recording...")
        
        let duration = audioRecorder?.currentTime ?? 0
        logger.debug("Recording duration: \(String(format: "%.2f", duration))s")
        
        stopMeteringTimer()
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
    
    // MARK: - Metering
    
    private func startMeteringTimer() {
        stopMeteringTimer()
        let timer = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(meterTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        meteringTimer = timer
    }
    
    private func stopMeteringTimer() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }
    
    @objc private func meterTick() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        onLevelUpdate?(OverlayMetrics.normalizedLevel(db: db))
    }
}