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
        Polish and improve the following transcribed text while preserving its original meaning:
        - Fix punctuation and grammar
        - Improve clarity and readability
        - Maintain natural language flow
        - Keep technical terms intact
        - Return only the polished text without any explanations
        
        Do not add or remove content from the original message.
        """,
        baseURL: nil,
        timeout: 5.0,
        pinnedProfile: nil,
        useAppSpecificPolish: true
    )
}
