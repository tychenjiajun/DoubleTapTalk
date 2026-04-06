import Foundation

final class ASRService {
    private var currentBackend: ASRBackend?
    private let logger = FileLogger.shared
    
    init() {
        updateBackend()
    }
    
    func updateBackend() {
        let settings = VoiceKeySettings.shared
        
        switch settings.backendType {
        case .openAI:
            currentBackend = OpenAIWhisperBackend(apiKey: settings.apiKey, apiURL: settings.apiURL)
        case .groq:
            currentBackend = GroqBackend(apiKey: settings.apiKey, apiURL: settings.apiURL)
        case .qwen:
            currentBackend = QwenASRBackend(apiKey: settings.apiKey, apiURL: settings.apiURL)
        case .local:
            currentBackend = LocalWhisperBackend(apiURL: settings.apiURL)
        }
    }
    
    func transcribe(audioURL: URL) async throws -> String? {
        // Update backend in case settings changed
        updateBackend()
        
        guard let backend = currentBackend else {
            logger.log("No backend configured")
            throw ASRError.invalidURL
        }
        
        logger.log("Using backend: \(backend.name)")
        
        let settings = VoiceKeySettings.shared
        logger.log("API Key exists: \(settings.apiKey != nil ? "yes" : "no")")
        logger.log("Transcribing with model: \(settings.model), language: \(settings.language)")
        
        do {
            let result = try await backend.transcribe(
                audioURL: audioURL,
                language: settings.language == "auto" ? nil : settings.language,
                model: settings.model
            )
            
            logger.log("Got transcription: '\(result.text)'")
            return result.text
        } catch {
            logger.log("Transcription error: \(error)")
            throw error
        }
    }
}