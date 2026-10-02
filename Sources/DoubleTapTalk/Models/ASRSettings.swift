import Foundation

/// Configuration for cloud transcription of the recorded audio via an
/// OpenAI-compatible ASR endpoint (e.g. Aliyun DashScope `qwen3-asr-flash`
/// in compatible-mode). Tried *after* recording stops; on ANY failure the
/// pipeline falls back to Apple's on-device result.
///
/// Live partial text during recording is always Apple's on-device stream —
/// the cloud result only replaces the final injected text.
struct ASRSettings {
    var enabled: Bool
    /// OpenAI-compatible base URL, e.g.
    /// `https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1`.
    /// The service appends `/chat/completions`.
    var baseURL: String?
    var apiKey: String?
    var model: String
    /// Language hint forwarded to the ASR endpoint (from the app's language
    /// setting; "auto" lets the model detect — captured here so the service
    /// never reads the settings singleton itself).
    var language: String

    static let defaultModel = "qwen3-asr-flash"

    static let `default` = ASRSettings(
        enabled: false,
        baseURL: nil,
        apiKey: nil,
        model: defaultModel,
        language: "auto"
    )

    /// Builds an ASR snapshot from global settings. Falls back to the LLM
    /// base URL / API key when the ASR-specific ones are empty, so a single
    /// DashScope-style endpoint can power both polishing and transcription.
    static func current() -> ASRSettings {
        let s = DoubleTapTalkSettings.shared
        let baseURL = (s.asrBaseURL?.isEmpty == false) ? s.asrBaseURL : s.llmBaseURL
        let apiKey: String?
        if s.asrAPIKey?.isEmpty == false {
            apiKey = s.asrAPIKey
        } else if s.llmAPIKey?.isEmpty == false {
            apiKey = s.llmAPIKey
        } else {
            apiKey = nil
        }
        return ASRSettings(
            enabled: s.asrEnabled,
            baseURL: baseURL,
            apiKey: apiKey,
            model: s.asrModel.isEmpty ? defaultModel : s.asrModel,
            language: s.language
        )
    }
}