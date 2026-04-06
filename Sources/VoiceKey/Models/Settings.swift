import Foundation

private let logger = FileLogger.shared

enum ASRBackendType: String, CaseIterable, Codable {
    case openAI = "openai"
    case groq = "groq"
    case qwen = "qwen"
    case local = "local"
    
    var displayName: String {
        switch self {
        case .openAI: return "OpenAI Whisper"
        case .groq: return "Groq"
        case .qwen: return "Qwen3 ASR"
        case .local: return "Local (whisper.cpp)"
        }
    }
    
    var requiresAPIKey: Bool {
        switch self {
        case .openAI, .groq, .qwen: return true
        case .local: return false
        }
    }
    
    var defaultURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1/audio/transcriptions"
        case .groq: return "https://api.groq.com/openai/v1/audio/transcriptions"
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        case .local: return "http://localhost:8080/v1/audio/transcriptions"
        }
    }
}

final class VoiceKeySettings: ObservableObject {
    static let shared = VoiceKeySettings()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let backendType = "ASRBackendType"
        static let apiURL = "ASRAPIURL"
        static let language = "ASRLanguage"
        static let model = "ASRModel"
        static let useLocalServer = "UseLocalServer"
    }
    
    @Published var backendType: ASRBackendType {
        didSet {
            logger.info("Settings: Backend changed to \(backendType.displayName)")
            defaults.set(backendType.rawValue, forKey: Keys.backendType)
            // Update URL when backend changes
            apiURL = backendType.defaultURL
        }
    }
    
    @Published var apiURL: String {
        didSet {
            defaults.set(apiURL, forKey: Keys.apiURL)
        }
    }
    
    @Published var language: String {
        didSet {
            defaults.set(language, forKey: Keys.language)
        }
    }
    
    @Published var model: String {
        didSet {
            defaults.set(model, forKey: Keys.model)
        }
    }
    
    @Published var useLocalServer: Bool {
        didSet {
            defaults.set(useLocalServer, forKey: Keys.useLocalServer)
        }
    }
    
    var apiKey: String? {
        get {
            let key = KeychainService.shared.getAPIKey(for: backendType)
            logger.debug("Settings: API key exists for \(backendType.rawValue): \(key != nil ? "yes" : "no")")
            return key
        }
        set {
            if let newValue = newValue {
                logger.info("Settings: Saving API key for \(backendType.rawValue)")
                KeychainService.shared.saveAPIKey(newValue, for: backendType)
            } else {
                logger.info("Settings: Deleting API key for \(backendType.rawValue)")
                KeychainService.shared.deleteAPIKey(for: backendType)
            }
        }
    }
    
    private init() {
        // Load saved settings or use defaults
        let savedBackend = defaults.string(forKey: Keys.backendType) ?? ASRBackendType.openAI.rawValue
        let backend = ASRBackendType(rawValue: savedBackend) ?? .openAI
        self.backendType = backend
        self.apiURL = defaults.string(forKey: Keys.apiURL) ?? backend.defaultURL
        self.language = defaults.string(forKey: Keys.language) ?? "auto"
        
        // Set appropriate default model based on backend
        if backend == .openAI {
            self.model = defaults.string(forKey: Keys.model) ?? "whisper-1"
        } else if backend == .groq {
            self.model = defaults.string(forKey: Keys.model) ?? "whisper-large-v3-turbo"
        } else if backend == .qwen {
            self.model = defaults.string(forKey: Keys.model) ?? "qwen3-asr-flash"
        } else {
            self.model = defaults.string(forKey: Keys.model) ?? "whisper.cpp"
        }
        
        self.useLocalServer = defaults.bool(forKey: Keys.useLocalServer)
    }
    
    func reset() {
        backendType = .openAI
        apiURL = ASRBackendType.openAI.defaultURL
        language = "auto"
        model = "whisper-1"
        useLocalServer = false
    }
}