import Foundation
import AppKit

enum LLMProvider: String, CaseIterable, Codable {
    case openai = "openai"
    case anthropic = "anthropic"
    case google = "google"
    
    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic (Claude)"
        case .google: return "Google (Gemini)"
        }
    }
    
    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .anthropic: return "claude-3-haiku-20240307"
        case .google: return "gemini-1.5-flash"
        }
    }
    
    var baseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .anthropic: return "https://api.anthropic.com/v1/messages"
        case .google: return "https://generativelanguage.googleapis.com/v1beta/models"
        }
    }
}

struct LLMSettings: Codable {
    var enabled: Bool
    var provider: LLMProvider
    var apiKey: String?
    var model: String
    var temperature: Double
    var systemPrompt: String
    var baseURL: String?  // Optional custom base URL for OpenAI-compatible APIs
    var timeout: Double   // Timeout in seconds for polishing operation
    var pinnedProfile: PolishProfile?  // User-pinned profile, nil = auto-detect
    var useAppSpecificPolish: Bool     // Enable context-aware profiles
    
    static let `default` = LLMSettings(
        enabled: false,
        provider: .openai,
        apiKey: nil,
        model: "gpt-4o-mini",
        temperature: 0.3,
        systemPrompt: """
        Polish this transcribed text conservatively: fix obvious speech-recognition errors and punctuation only. Never rewrite, add, or translate — keep the original language. Output only the polished text.
        """,
        baseURL: nil,
        timeout: 5.0,
        pinnedProfile: nil,
        useAppSpecificPolish: true
    )
    
    /// Builds an LLMSettings snapshot from the global app settings (DRY:
    /// single source for the polish configuration used by every pipeline).
    static func current() -> LLMSettings {
        let settings = DoubleTapTalkSettings.shared
        return LLMSettings(
            enabled: settings.llmEnabled,
            provider: settings.llmProvider,
            apiKey: settings.llmAPIKey,
            model: settings.llmModel,
            temperature: settings.llmTemperature,
            systemPrompt: settings.llmSystemPrompt,
            baseURL: settings.llmBaseURL,
            timeout: settings.llmTimeout,
            pinnedProfile: settings.pinnedPolishProfile,
            useAppSpecificPolish: settings.useAppSpecificPolish
        )
    }
}
