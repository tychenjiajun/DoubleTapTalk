import Foundation

struct OpenAIWhisperBackend: ASRBackend {
    let name = "OpenAI Whisper"
    private let apiKey: String?
    private let apiURL: String
    private let logger = FileLogger.shared
    
    init(apiKey: String?, apiURL: String) {
        self.apiKey = apiKey
        self.apiURL = apiURL
    }
    
    func transcribe(audioURL: URL, language: String?, model: String?) async throws -> ASRResult {
        logger.info("OpenAI Whisper: Starting transcription")
        logger.debug("API URL: \(apiURL)")
        logger.debug("Model: \(model ?? "whisper-1"), Language: \(language ?? "auto")")
        
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            logger.error("OpenAI Whisper: No API key configured")
            throw ASRError.noAPIKey
        }
        
        guard let url = URL(string: apiURL) else {
            logger.error("OpenAI Whisper: Invalid API URL: \(apiURL)")
            throw ASRError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Build multipart form data
        var body = Data()
        
        // Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model ?? "whisper-1")\r\n".data(using: .utf8)!)
        
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
        logger.debug("Sending request to OpenAI API...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("OpenAI Whisper: Invalid response type")
            throw ASRError.invalidResponse
        }
        
        logger.debug("OpenAI API response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("OpenAI Whisper API error (\(httpResponse.statusCode)): \(errorMessage)")
            throw ASRError.serverError(httpResponse.statusCode, errorMessage)
        }
        
        // Log raw response for debugging
        if let rawResponse = String(data: data, encoding: .utf8) {
            logger.debug("Raw API response length: \(rawResponse.count) chars")
            logger.debug("Raw API response: \(rawResponse)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("OpenAI Whisper: Failed to parse response JSON")
            throw ASRError.invalidResponse
        }
        
        // Try different possible field names for transcription result
        var text: String?
        if let t = json["text"] as? String {
            text = t
        } else if let t = json["text"] as? [String], let first = t.first {
            text = first  // Handle array response
        } else if let segments = json["segments"] as? [[String: Any]], !segments.isEmpty {
            // Some APIs return segments array
            text = segments.compactMap { $0["text"] as? String }.joined()
        }
        
        guard let transcript = text, !transcript.isEmpty else {
            logger.error("OpenAI Whisper: No transcription text found in response")
            logger.error("Full JSON keys: \(json.keys.joined(separator: ", "))")
            throw ASRError.transcriptionFailed("Empty response from API")
        }
        
        logger.info("OpenAI Whisper: Transcription successful (\(transcript.count) chars)")
        return ASRResult(
            text: transcript,
            language: json["language"] as? String,
            confidence: nil,
            duration: nil
        )
    }
}