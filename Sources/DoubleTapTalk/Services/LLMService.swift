import Foundation
import AppKit

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
    
    /// Strip leading/trailing markdown code block markers while preserving internal markdown
    private func stripMarkdownCodeBlocks(_ text: String) -> String {
        var result = text
        
        // Strip leading ``` with optional language specifier
        // Pattern: ``` at start, possibly followed by language name on same line
        if result.hasPrefix("```") {
            // Find the first newline after ```
            if let firstNewlineIndex = result.firstIndex(of: "\n") {
                // Check if there's a language specifier between ``` and newline
                let afterBackticks = result[result.index(result.startIndex, offsetBy: 3)..<firstNewlineIndex]
                let langSpecifier = String(afterBackticks).trimmingCharacters(in: .whitespaces)
                // If langSpecifier is empty or a valid language name, remove the opening block
                if langSpecifier.isEmpty || langSpecifier.count < 20 {
                    result = String(result[result.index(after: firstNewlineIndex)...])
                } else {
                    // Unusual case - just remove the ```
                    result = String(result.dropFirst(3))
                }
            } else {
                // No newline - just remove ```
                result = String(result.dropFirst(3))
            }
        }
        
        // Strip trailing ```
        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Context-Aware Polishing
    
    /// Polish text using context-aware profiles
    func polish(
        text: String,
        settings: LLMSettings,
        context: PolishContext?
    ) async throws -> String {
        guard settings.enabled else {
            logger.debug("LLM polishing disabled, returning original text")
            return text
        }
        
        guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
            logger.warning("LLM polishing enabled but no API key configured")
            return text
        }
        
        // Use context-aware profile if available and enabled
        if settings.useAppSpecificPolish, let context = context {
            return try await polishWithContextAwareProfile(text: text, settings: settings, context: context)
        }
        
        // Fallback to legacy mode with custom system prompt
        logger.info("Using legacy mode with custom system prompt")
        return try await polishWithCustomPrompt(text: text, settings: settings)
    }
    
    private func polishWithContextAwareProfile(
        text: String,
        settings: LLMSettings,
        context: PolishContext
    ) async throws -> String {
        logger.info("Polishing text with context-aware profile")
        logger.debug("Target app: \(context.targetApp.appName), locale: \(context.userLocale)")
        
        // Auto-detect or use pinned profile
        let profile: PolishProfile = settings.pinnedProfile ?? .detect(from: context.targetApp)
        
        logger.info("Polish profile: \(profile.rawValue) | app: \(context.targetApp.appName)")
        
        // Log terminal-specific context if applicable
        if profile == .terminal {
            logger.info("=== TERMINAL POLISH DEBUG ===")
            logger.debug("Original ASR text: '\(text)'")
            logger.debug("Target app bundle ID: \(context.targetApp.bundleID ?? "unknown")")
            logger.debug("Existing field text (first 200 chars): \((context.existingText?.prefix(200) ?? "none"))")
            logger.debug("Terminal screen context (first 500 chars): \((context.conversationHint?.prefix(500) ?? "none"))...")
        }
        
        // Build the context-aware prompt
        let systemPrompt = profile.systemPrompt(context: context)
        
        // Log the complete prompt being sent to LLM for debugging
        logger.debug("=== LLM REQUEST DEBUG ===")
        logger.debug("System prompt length: \(systemPrompt.count) chars")
        if systemPrompt.count < 1000 {
            logger.debug("System prompt:\n\(systemPrompt)")
        } else {
            logger.debug("System prompt (first 500 chars):\n\(systemPrompt.prefix(500))...")
        }
        
        // Wrap user content with profile-specific framing
        let userContent = wrapUserContent(text, profile: profile)
        logger.debug("User content (polished): '\(userContent)'")
        
        let response = try await callLLM(
            provider: settings.provider,
            apiKey: settings.apiKey!,
            model: settings.model,
            systemPrompt: systemPrompt,
            userContent: userContent,
            baseURL: settings.baseURL
        )
        
        logger.info("Polished text (first 200 chars): \(response.prefix(200))\(response.count > 200 ? "..." : "")")
        logger.debug("Polished text final: '\(response)' (\(response.count) chars)")
        logger.info("=== END POLISH DEBUG ===")
        return response
    }
    
    private func polishWithCustomPrompt(text: String, settings: LLMSettings) async throws -> String {
        logger.info("Polishing text with custom system prompt")
        logger.debug("Original text (first 100 chars): \(text.prefix(100))\(text.count > 100 ? "..." : "")")
        
        let response = try await callLLM(
            provider: settings.provider,
            apiKey: settings.apiKey!,
            model: settings.model,
            systemPrompt: settings.systemPrompt,
            userContent: text,
            baseURL: settings.baseURL
        )
        
        logger.info("Polished text (first 100 chars): \(response.prefix(100))\(response.count > 100 ? "..." : "")")
        return response
    }
    
    private func wrapUserContent(_ text: String, profile: PolishProfile) -> String {
        // Use neutral framing - the system prompt already establishes the context
        // Avoid contradictory instructions like "Convert to X" when the prompt says "preserve original"
        switch profile {
        case .terminal:
            return "Speech to polish: \(text)"
        case .searchQuery:
            return "Speech to polish: \(text)"
        case .codeComment:
            return "Speech to polish: \(text)"
        case .codeEditor:
            return "Speech to polish: \(text)"
        case .tradingTerminal:
            return "Speech to polish: \(text)"
        case .chatMessaging:
            return "Speech to polish: \(text)"
        case .emailFormal:
            return "Speech to polish: \(text)"
        case .general:
            return "Speech to polish: \(text)"
        }
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
        
        // Log full response for debugging
        if let responseBody = String(data: data, encoding: .utf8) {
            logger.debug("Full OpenAI response: \(responseBody.prefix(500))\(responseBody.count > 500 ? "..." : "")")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Invalid JSON response")
            throw ASRError.invalidResponse
        }
        
        // Try multiple parsing strategies for different API formats
        var content: String?
        
        // Strategy 1: Standard OpenAI format
        if let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let text = message["content"] as? String {
            content = text
            logger.debug("Parsed using standard OpenAI format")
        }
        // Strategy 2: ModelScope/Tongyi format (text in root or alternatives)
        else if let text = json["output"] as? [String: Any],
                let choices = text["choices"] as? [[String: Any]],
                let firstChoice = choices.first,
                let textValue = firstChoice["text"] as? String {
            content = textValue
            logger.debug("Parsed using ModelScope output.choices[].text format")
        }
        else if let text = json["text"] as? String {
            content = text
            logger.debug("Parsed using root.text format")
        }
        // Strategy 3: Alternative common formats
        else if let reply = json["reply"] as? String {
            content = reply
            logger.debug("Parsed using root.reply format")
        }
        else {
            logger.error("Unknown response format. Available keys: \(json.keys)")
            logger.error("Raw JSON: \(json)")
            throw ASRError.invalidResponse
        }
        
        return stripMarkdownCodeBlocks(content!)
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
        
        return stripMarkdownCodeBlocks(content)
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
        
        return stripMarkdownCodeBlocks(text)
    }
}
