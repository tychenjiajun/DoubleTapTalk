import Foundation

struct GroqBackend: ASRBackend {
    let name = "Groq"
    private let apiKey: String?
    private let apiURL: String
    private let logger = FileLogger.shared
    
    init(apiKey: String?, apiURL: String) {
        self.apiKey = apiKey
        self.apiURL = apiURL
    }
    
    func transcribe(audioURL: URL, language: String?, model: String?) async throws -> ASRResult {
        logger.info("Groq: Starting transcription")
        logger.debug("API URL: \(apiURL)")
        logger.debug("Model: \(model ?? "whisper-1"), Language: \(language ?? "auto")")
        
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            logger.error("Groq: No API key configured")
            throw ASRError.noAPIKey
        }
        
        guard let url = URL(string: apiURL) else {
            logger.error("Groq: Invalid API URL: \(apiURL)")
            throw ASRError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Build multipart form data
        var body = Data()
        
        // Model field - Groq uses different model names
        let modelName = model ?? "whisper-1"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(modelName)\r\n".data(using: .utf8)!)
        
        // Language field (optional)
        if let language = language, language != "auto" {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
        }
        
        // Response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("json\r\n".data(using: .utf8)!)
        
        // Audio file
        let audioData = try Data(contentsOf: audioURL)
        logger.debug("Audio file size: \(audioData.count) bytes")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        logger.debug("Sending request to Groq API...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Groq: Invalid response type")
            throw ASRError.invalidResponse
        }
        
        logger.debug("Groq API response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Groq API error (\(httpResponse.statusCode)): \(errorMessage)")
            throw ASRError.serverError(httpResponse.statusCode, errorMessage)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            logger.error("Groq: Failed to parse response JSON")
            throw ASRError.invalidResponse
        }
        
        logger.info("Groq: Transcription successful (\(text.count) chars)")
        return ASRResult(
            text: text,
            language: json["language"] as? String,
            confidence: nil,
            duration: nil
        )
    }
}