import Foundation

private let logger = FileLogger.shared

/// Transcripts the recorded audio via an OpenAI-compatible ASR endpoint
/// (e.g. Aliyun DashScope `qwen3-asr-flash` in compatible-mode, which accepts
/// an `input_audio` content block with a base64 data URL).
///
/// Designed for graceful degradation: every failure path returns nil so the
/// caller falls back to Apple's on-device transcription. Never throws.
final class CloudTranscriptionService {
    static let shared = CloudTranscriptionService()

    enum Limits {
        /// OpenAI-compatible ASR input cap for base64 data (qwen3-asr-flash).
        static let maxFileSize = 10 * 1024 * 1024 // 10 MB
    }

    private let logger = FileLogger.shared
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        self.session = URLSession(configuration: config)
    }

    /// Uploads `fileURL` to the configured endpoint and returns the transcribed
    /// text, or nil when disabled/unconfigured/failed (caller falls back to
    /// Apple's on-device result).
    func transcribe(fileURL: URL, settings: ASRSettings) async -> String? {
        guard settings.enabled else { return nil }

        guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
            logger.warning("Cloud transcription enabled but no API key configured — falling back to Apple")
            return nil
        }
        guard let baseURL = settings.baseURL, !baseURL.isEmpty,
              let endpoint = Self.endpointURL(for: baseURL) else {
            logger.warning("Cloud transcription enabled but no valid base URL configured — falling back to Apple")
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            logger.warning("Cloud transcription: recording file is empty or unreadable — falling back to Apple")
            return nil
        }
        guard data.count <= Limits.maxFileSize else {
            logger.error("Cloud transcription: recording is \(data.count) bytes (> 10 MB limit) — falling back to Apple")
            return nil
        }

        let languageCode = settings.language
        let dataURL = "data:audio/wav;base64," + data.base64EncodedString()
        let body: Data
        do {
            body = try Self.buildRequestBody(model: settings.model, dataURL: dataURL, language: languageCode)
        } catch {
            logger.error("Cloud transcription: could not encode request body: \(error) — falling back to Apple")
            return nil
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        logger.info("Cloud transcription request → \(endpoint.absoluteString) (model: \(settings.model), \(data.count) bytes audio)")

        do {
            let (responseData, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let body = String(data: responseData, encoding: .utf8) ?? "<non-UTF8>"
                logger.error("Cloud transcription HTTP \(http.statusCode): \(body.prefix(300))")
                return nil
            }
            let text = try Self.parseTranscription(from: responseData)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                logger.error("Cloud transcription returned empty text — falling back to Apple")
                return nil
            }
            logger.info("✓ Cloud transcription: '\(text.prefix(120))\(text.count > 120 ? "…" : "")'")
            return text
        } catch {
            logger.error("Cloud transcription failed: \(error) — falling back to Apple")
            return nil
        }
    }

    // MARK: - Pure, testable helpers

    /// Normalizes a base URL to the chat-completions endpoint.
    /// - `https://host/v1`            → `https://host/v1/chat/completions`
    /// - `https://host/v1/`           → `https://host/v1/chat/completions`
    /// - `https://host/v1/chat/completions` → unchanged
    static func endpointURL(for baseURL: String) -> URL? {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.hasSuffix("/chat/completions") {
            if trimmed.hasSuffix("/") { trimmed.removeLast() }
            trimmed += "/chat/completions"
        }
        return URL(string: trimmed)
    }

    /// Builds the OpenAI-compatible request body with an `input_audio` block.
    /// `asr_options` is a DashScope extension — only attached for ASR models so
    /// a plain OpenAI-compatible chat endpoint isn't sent unknown params.
    /// Throws (instead of returning an empty body) so the caller falls back.
    static func buildRequestBody(model: String, dataURL: String, language: String? = nil, includeASROptions: Bool? = nil) throws -> Data {
        let content: [String: Any] = [
            "type": "input_audio",
            "input_audio": ["data": dataURL],
        ]
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": [content]]],
            "stream": false,
        ]
        let addASROptions = includeASROptions ?? (model.lowercased().contains("asr"))
        if addASROptions {
            var options: [String: Any] = ["enable_itn": false]
            if let language = language, language != "auto", !language.isEmpty {
                options["language"] = language
            }
            body["asr_options"] = options
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    /// Extracts `choices[0].message.content` from a chat-completions response.
    static func parseTranscription(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PipelineError.invalidResponse
        }
        return content
    }
}