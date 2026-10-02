import Foundation
import AppKit

private let logger = FileLogger.shared

/// Global app settings. Speech recognition is fixed to Apple's on-device
/// backend — the only remaining settings concern language + LLM polishing.
final class DoubleTapTalkSettings: ObservableObject {
    static let shared = DoubleTapTalkSettings()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let language = "ASRLanguage"
        // LLM Polishing keys
        static let llmEnabled = "LLMEnabled"
        static let llmProvider = "LLMProvider"
        static let llmModel = "LLMModel"
        static let llmTemperature = "LLMTemperature"
        static let llmSystemPrompt = "LLMSystemPrompt"
        static let llmBaseURL = "LLMBASEURL"
        static let llmTimeout = "LLMTimeout"
        static let useAppSpecificPolish = "UseAppSpecificPolish"
        static let pinnedPolishProfile = "PinnedPolishProfile"
        // Cloud transcription (OpenAI-compatible ASR) keys
        static let asrEnabled = "ASREnabled"
        static let asrBaseURL = "ASRBaseURL"
        static let asrAPIKey = "ASRAPIKey"
        static let asrModel = "ASRModel"
        // Continuous dictation (relay) keys
        static let relayEnabled = "RelayEnabled"
        static let relayIdleThreshold = "RelayIdleThreshold"
    }
    
    @Published var language: String {
        didSet {
            defaults.set(language, forKey: Keys.language)
        }
    }
    
    // MARK: - LLM Polishing Settings
    
    @Published var llmEnabled: Bool {
        didSet {
            defaults.set(llmEnabled, forKey: Keys.llmEnabled)
            logger.info("Settings: LLM polishing \(llmEnabled ? "enabled" : "disabled")")
        }
    }
    
    @Published var llmProvider: LLMProvider {
        didSet {
            defaults.set(llmProvider.rawValue, forKey: Keys.llmProvider)
            logger.info("Settings: LLM provider changed to \(llmProvider.displayName)")
            if llmProvider != oldValue {
                llmModel = llmProvider.defaultModel
            }
        }
    }
    
    @Published var llmModel: String {
        didSet {
            defaults.set(llmModel, forKey: Keys.llmModel)
        }
    }
    
    @Published var llmTemperature: Double {
        didSet {
            defaults.set(llmTemperature, forKey: Keys.llmTemperature)
        }
    }
    
    var llmSystemPrompt: String {
        get { defaults.string(forKey: Keys.llmSystemPrompt) ?? LLMSettings.default.systemPrompt }
        set { defaults.set(newValue, forKey: Keys.llmSystemPrompt) }
    }
    
    @Published var llmBaseURL: String? = nil {
        didSet {
            defaults.set(llmBaseURL, forKey: Keys.llmBaseURL)
            logger.info("Settings: LLM Base URL \(llmBaseURL != nil ? "saved" : "cleared")")
        }
    }
    
    @Published var llmTimeout: Double = 5.0 {
        didSet {
            defaults.set(llmTimeout, forKey: Keys.llmTimeout)
            logger.info("Settings: LLM Timeout \(llmTimeout)s saved")
        }
    }
    
    @Published var llmAPIKey: String? = nil {
        didSet {
            defaults.set(llmAPIKey, forKey: "LLMAPIKey")
            logger.info("Settings: LLM API key \(llmAPIKey != nil ? "saved" : "cleared")")
        }
    }
    
    @Published var useAppSpecificPolish: Bool {
        didSet {
            defaults.set(useAppSpecificPolish, forKey: Keys.useAppSpecificPolish)
            logger.info("Settings: App-specific polish \(useAppSpecificPolish ? "enabled" : "disabled")")
        }
    }
    
    var pinnedPolishProfile: PolishProfile? {
        get {
            guard let rawValue = defaults.string(forKey: Keys.pinnedPolishProfile) else { return nil }
            return PolishProfile(rawValue: rawValue)
        }
        set {
            defaults.set(newValue?.rawValue, forKey: Keys.pinnedPolishProfile)
        }
    }
    
    // MARK: - Cloud Transcription Settings (OpenAI-compatible ASR)

    @Published var asrEnabled: Bool {
        didSet {
            defaults.set(asrEnabled, forKey: Keys.asrEnabled)
            logger.info("Settings: Cloud transcription \(asrEnabled ? "enabled" : "disabled")")
        }
    }

    @Published var asrModel: String {
        didSet {
            defaults.set(asrModel, forKey: Keys.asrModel)
        }
    }

    @Published var asrBaseURL: String? = nil {
        didSet {
            defaults.set(asrBaseURL, forKey: Keys.asrBaseURL)
            logger.info("Settings: Cloud ASR base URL \(asrBaseURL != nil ? "saved" : "cleared")")
        }
    }

    @Published var asrAPIKey: String? = nil {
        didSet {
            defaults.set(asrAPIKey, forKey: Keys.asrAPIKey)
            logger.info("Settings: Cloud ASR API key \(asrAPIKey != nil ? "saved" : "cleared")")
        }
    }

    // MARK: - Continuous Dictation (Relay) Settings

    /// When on, the microphone stays open across segments: after `relayIdleThreshold`
    /// seconds without new words the current segment is recognized + inserted and
    /// a new one starts — one long dictation with thinking pauses in between.
    @Published var relayEnabled: Bool {
        didSet {
            defaults.set(relayEnabled, forKey: Keys.relayEnabled)
            logger.info("Settings: Continuous dictation \(relayEnabled ? "enabled" : "disabled")")
        }
    }

    @Published var relayIdleThreshold: Double {
        didSet {
            defaults.set(relayIdleThreshold, forKey: Keys.relayIdleThreshold)
            logger.info("Settings: Relay idle threshold \(relayIdleThreshold)s saved")
        }
    }

    private init() {
        self.language = defaults.string(forKey: Keys.language) ?? "auto"
        
        // Load app-specific polish setting (must load before other LLM settings that may reference it)
        // Default to true for new installs, respect saved value for existing users
        if defaults.object(forKey: Keys.useAppSpecificPolish) == nil {
            defaults.set(true, forKey: Keys.useAppSpecificPolish)
        }
        self.useAppSpecificPolish = defaults.bool(forKey: Keys.useAppSpecificPolish)
        
        // Load LLM polishing settings
        let llmEnabledValue = defaults.bool(forKey: Keys.llmEnabled)
        self.llmEnabled = llmEnabledValue
        let savedProvider = defaults.string(forKey: Keys.llmProvider) ?? "openai"
        let provider = LLMProvider(rawValue: savedProvider) ?? .openai
        self.llmProvider = provider
        self.llmModel = defaults.string(forKey: Keys.llmModel) ?? "gpt-4o-mini"
        let tempValue = defaults.double(forKey: Keys.llmTemperature)
        self.llmTemperature = tempValue == 0.0 ? 0.3 : tempValue
        self.llmBaseURL = defaults.string(forKey: Keys.llmBaseURL)
        let timeoutValue = defaults.double(forKey: Keys.llmTimeout)
        self.llmTimeout = timeoutValue > 0.0 ? timeoutValue : 5.0

        // Initialize cloud transcription stored properties before any computed
        // property access (Swift definite-initialization rule).
        self.asrEnabled = defaults.bool(forKey: Keys.asrEnabled)
        self.asrModel = defaults.string(forKey: Keys.asrModel) ?? ASRSettings.defaultModel
        self.asrBaseURL = defaults.string(forKey: Keys.asrBaseURL)
        self.asrAPIKey = defaults.string(forKey: Keys.asrAPIKey)

        // Load continuous dictation settings. Relay is OPT-IN (default OFF):
        // it changes the core UX (mic stays open, auto-split + auto-insert),
        // so existing users must not get it on upgrade without asking.
        self.relayEnabled = defaults.bool(forKey: Keys.relayEnabled)
        let relayThreshold = defaults.double(forKey: Keys.relayIdleThreshold)
        self.relayIdleThreshold = relayThreshold > 0.0 ? relayThreshold : 3.0

        self.llmSystemPrompt = defaults.string(forKey: Keys.llmSystemPrompt) ?? LLMSettings.default.systemPrompt
        self.llmAPIKey = defaults.string(forKey: "LLMAPIKey")
    }
    
    func reset() {
        language = "auto"
        
        // Reset LLM polishing settings
        llmEnabled = false
        llmProvider = .openai
        llmModel = "gpt-4o-mini"
        llmTemperature = 0.3
        useAppSpecificPolish = true  // Default to enabled

        // Reset cloud transcription settings
        asrEnabled = false
        asrModel = ASRSettings.defaultModel
        asrBaseURL = nil
        asrAPIKey = nil

        // Reset continuous dictation settings
        relayEnabled = false
        relayIdleThreshold = 3.0
    }
}