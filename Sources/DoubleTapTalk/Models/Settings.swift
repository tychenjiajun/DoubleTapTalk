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
        static let llmAPIKey = "LLMAPIKey"
        static let llmTimeout = "LLMTimeout"
        static let useAppSpecificPolish = "UseAppSpecificPolish"
        static let pinnedPolishProfile = "PinnedPolishProfile"
        // Cloud transcription (OpenAI-compatible ASR) keys
        static let asrEnabled = "ASREnabled"
        static let asrBaseURL = "ASRBaseURL"
        static let asrAPIKey = "ASRAPIKey"
        static let asrModel = "ASRModel"
        // Continuous dictation (relay) keys
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
    
    /// Secrets live in the Keychain (see `persistSecret`); UserDefaults only
    /// holds a plaintext copy when the Keychain rejects the write.
    @Published var llmAPIKey: String? = nil {
        didSet {
            persistSecret(llmAPIKey, keychainKey: KeychainStore.Account.llmAPIKey, defaultsKey: Keys.llmAPIKey)
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
            persistSecret(asrAPIKey, keychainKey: KeychainStore.Account.asrAPIKey, defaultsKey: Keys.asrAPIKey)
            logger.info("Settings: Cloud ASR API key \(asrAPIKey != nil ? "saved" : "cleared")")
        }
    }

    // MARK: - Continuous Dictation (Relay) Settings

    /// The microphone stays open across segments: after `relayIdleThreshold`
    /// seconds without new words the current segment is recognized + inserted
    /// and a new one starts — one long dictation with thinking pauses in
    /// between. Continuous dictation is the ONLY mode (relay is always on).
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
        // object(forKey:) distinguishes "never set" from an explicit 0.0 —
        // the old `tempValue == 0.0` mapping made a deliberate 0 impossible.
        self.llmTemperature = defaults.object(forKey: Keys.llmTemperature) == nil
            ? 0.3
            : defaults.double(forKey: Keys.llmTemperature)
        self.llmBaseURL = defaults.string(forKey: Keys.llmBaseURL)
        let timeoutValue = defaults.double(forKey: Keys.llmTimeout)
        self.llmTimeout = timeoutValue > 0.0 ? timeoutValue : 5.0

        // Initialize cloud transcription stored properties before any computed
        // property access (Swift definite-initialization rule).
        self.asrEnabled = defaults.bool(forKey: Keys.asrEnabled)
        self.asrModel = defaults.string(forKey: Keys.asrModel) ?? ASRSettings.defaultModel
        self.asrBaseURL = defaults.string(forKey: Keys.asrBaseURL)
        self.asrAPIKey = Self.readSecret(keychainKey: KeychainStore.Account.asrAPIKey, defaultsKey: Keys.asrAPIKey)

        // Load continuous dictation settings (relay is the only mode).
        let relayThreshold = defaults.double(forKey: Keys.relayIdleThreshold)
        self.relayIdleThreshold = relayThreshold > 0.0 ? relayThreshold : 3.0

        self.llmSystemPrompt = defaults.string(forKey: Keys.llmSystemPrompt) ?? LLMSettings.default.systemPrompt
        self.llmAPIKey = Self.readSecret(keychainKey: KeychainStore.Account.llmAPIKey, defaultsKey: Keys.llmAPIKey)
    }

    /// Keychain first; a legacy plaintext copy in UserDefaults is migrated
    /// over (removed only once the Keychain write succeeded), and kept as-is
    /// when the Keychain refuses — never lose a working configuration.
    private static func readSecret(keychainKey: String, defaultsKey: String) -> String? {
        if let stored = KeychainStore.string(forKey: keychainKey) {
            return stored
        }
        guard let legacy = UserDefaults.standard.string(forKey: defaultsKey), !legacy.isEmpty else { return nil }
        if KeychainStore.set(legacy, forKey: keychainKey) {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            FileLogger.shared.info("Settings: migrated \(defaultsKey) into the Keychain")
        }
        return legacy
    }

    /// Writes a secret to the Keychain; on a Keychain failure it falls back
    /// to UserDefaults so the app keeps working (logged loudly — that copy is
    /// plaintext).
    private func persistSecret(_ value: String?, keychainKey: String, defaultsKey: String) {
        if KeychainStore.set(value, forKey: keychainKey) {
            // Also drops any legacy plaintext copy from before the migration.
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(value, forKey: defaultsKey)
            logger.warning("Keychain unavailable — secret kept in UserDefaults (plaintext)")
        }
    }
    
    func reset() {
        language = "auto"
        
        // Reset LLM polishing settings
        llmEnabled = false
        llmProvider = .openai
        llmModel = "gpt-4o-mini"
        llmTemperature = 0.3
        useAppSpecificPolish = true  // Default to enabled
        // Everything a user may have configured — a "reset" that leaves the
        // base URL / key / system prompt / timeout behind is not a reset.
        llmBaseURL = nil
        llmAPIKey = nil
        llmSystemPrompt = LLMSettings.default.systemPrompt
        llmTimeout = 5.0

        // Reset cloud transcription settings
        asrEnabled = false
        asrModel = ASRSettings.defaultModel
        asrBaseURL = nil
        asrAPIKey = nil

        // Reset continuous dictation settings
        relayIdleThreshold = 3.0
    }
}