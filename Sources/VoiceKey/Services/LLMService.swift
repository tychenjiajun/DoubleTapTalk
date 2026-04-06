import Foundation

final class LLMService {
    static let shared = LLMService()
    private let logger = FileLogger.shared
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    func polish(text: String, settings: LLMSettings) async throws -> String {
        guard settings.enabled else {
            logger.debug("LLM polishing disabled, returning original text")
            return text
        }
        
        guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
            logger.warning("LLM polishing enabled but no API key configured")
            return text
        }
        
        logger.info("Polishing text with \(settings.provider.displayName) - model: \(settings.model)")
        logger.debug("Original text (first 100 chars): \(text.prefix(100))\(text.count > 100 ? "..." : "")")
        
        let response = try await callLLM(
            provider: settings.provider,
            apiKey: apiKey,
            model: settings.model,
            systemPrompt: settings.systemPrompt,
            userContent: text,
            baseURL: settings.baseURL
        )
        
        logger.info("Polished text (first 100 chars): \(response.prefix(100))\(response.count > 100 ? "..." : "")")
        return response
    }
    
    private func callLLM(
        provider: LLMProvider,
        apiKey: String,
        model: String,
        systemPrompt: String,
        userContent: String,
        baseURL: String? = nil
    ) async throws -> String {
        switch provider {
        case .openai:
            return try await callOpenAI(apiKey: apiKey, model: model, systemPrompt: systemPrompt, userContent: userContent, baseURL: baseURL)
        case .anthropic:
            return try await callAnthropic(apiKey: apiKey, model: model, systemPrompt: systemPrompt, userContent: userContent)
        case .google:
            return try await callGoogle(apiKey: apiKey, model: model, systemPrompt: systemPrompt, userContent: userContent)
        }
    }
    
    private func callOpenAI(
        apiKey: String,
        model: String,
        systemPrompt: String,
        userContent: String,
        baseURL: String? = nil
    ) async throws -> String {
        // Use custom base URL if provided, otherwise use default
        let urlStr = baseURL?.trimmingCharacters(in: .whitespaces) != nil ? baseURL! : "https://api.openai.com/v1/chat/completions"
        guard var urlComponents = URLComponents(string: urlStr) else { throw URLError(.badURL) }
        
        // Ensure endpoint exists in URL
        if !urlComponents.path.hasSuffix("/chat/completions"), !urlComponents.path.isEmpty {
            urlComponents.path.append("/chat/completions")
        }
        
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.3
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        logger.debug("OpenAI HTTP Response: \(response)")
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("OpenAI API error: \(errorText)")
            throw ASRError.transcriptionFailed(errorText)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ASRError.invalidResponse
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func callAnthropic(
        apiKey: String,
        model: String,
        systemPrompt: String,
        userContent: String
    ) async throws -> String {
        let urlStr = "https://api.anthropic.com/v1/messages"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        logger.debug("Anthropic HTTP Response: \(response)")
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Anthropic API error: \(errorText)")
            throw ASRError.transcriptionFailed(errorText)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]],
              let firstContent = contentArray.first,
              let content = firstContent["text"] as? String else {
            throw ASRError.invalidResponse
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func callGoogle(
        apiKey: String,
        model: String,
        systemPrompt: String,
        userContent: String
    ) async throws -> String {
        let urlStr = "\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [
                    ["text": "\(systemPrompt)\n\nUser input: \(userContent)"]
                ]]
            ],
            "generationConfig": [
                "temperature": 0.3
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        logger.debug("Google HTTP Response: \(response)")
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Google API error: \(errorText)")
            throw ASRError.transcriptionFailed(errorText)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw ASRError.invalidResponse
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
