import Foundation
import AppKit

final class ASRService {
    private var currentBackend: ASRBackend?
    private let logger = FileLogger.shared
    
    init() {
        updateBackend()
    }
    
    func updateBackend() {
        let settings = DoubleTapTalkSettings.shared
        
        switch settings.backendType {
        case .openAI:
            currentBackend = OpenAIWhisperBackend(name: "OpenAI Whisper", apiKey: settings.apiKey, apiURL: settings.apiURL)
        case .groq:
            currentBackend = OpenAIWhisperBackend(name: "Groq", apiKey: settings.apiKey, apiURL: settings.apiURL)
        case .dashscope:
            currentBackend = DashscopeASRBackend(apiKey: settings.apiKey, apiURL: settings.apiURL)
        case .local:
            currentBackend = LocalWhisperBackend(apiURL: settings.apiURL)
        case .apple:
            // Apple streaming is handled by AppleSpeechBackend in the app pipeline,
            // not through the file-based backend protocol.
            currentBackend = nil
        }
    }
    
    func transcribe(audioURL: URL) async throws -> String {
        // Update backend in case settings changed
        updateBackend()
        
        guard let backend = currentBackend else {
            logger.info("No backend configured")
            throw ASRError.invalidURL
        }
        
        logger.info("Using backend: \(backend.name)")
        
        let settings = DoubleTapTalkSettings.shared
        logger.info("API Key exists: \(settings.apiKey != nil ? "yes" : "no")")
        logger.info("Transcribing with model: \(settings.model), language: \(settings.language)")
        let language: String? = settings.language == "auto" ? nil : settings.language
        
        do {
            // Try transcription with single retry for empty responses
            var result = try await backend.transcribe(
                audioURL: audioURL,
                language: language,
                model: settings.model
            )
            
            // Single retry if ASR returned empty result (API returned 200 but no content)
            if result.text.isEmpty {
                logger.warning("ASR returned empty result, retrying once...")
                result = try await backend.transcribe(
                    audioURL: audioURL,
                    language: language,
                    model: settings.model
                )
                if result.text.isEmpty {
                    logger.error("ASR still empty after retry")
                    throw ASRError.transcriptionFailed("Empty transcription after retry")
                }
            }
            
            let text = result.text
            logger.info("Got transcription: '\(text)'")
            return text
        } catch {
            logger.info("Transcription error: \(error)")
            throw error
        }
    }
}