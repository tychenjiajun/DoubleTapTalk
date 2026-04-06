import Foundation

struct QwenASRBackend: ASRBackend {
    let name = "Qwen3 ASR"
    private let apiKey: String?
    private let apiURL: String
    private let logger = FileLogger.shared
    
    init(apiKey: String?, apiURL: String) {
        self.apiKey = apiKey
        self.apiURL = apiURL
    }
    
    func transcribe(audioURL: URL, language: String?, model: String?) async throws -> ASRResult {
        logger.info("Qwen3 ASR: Starting transcription")
        logger.debug("API URL: \(apiURL)")
        logger.debug("Model: \(model ?? "qwen3-asr-flash"), Language: \(language ?? "auto")")
        
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            logger.error("Qwen3 ASR: No API key configured")
            throw ASRError.noAPIKey
        }
        
        guard let url = URL(string: apiURL) else {
            logger.error("Qwen3 ASR: Invalid API URL: \(apiURL)")
            throw ASRError.invalidURL
        }
        
        // Read and encode audio file as Base64
        let audioData = try Data(contentsOf: audioURL)
        let base64Audio = audioData.base64EncodedString()
        let mimeType = "audio/wav"  // We record WAV files
        let dataURI = "data:\(mimeType);base64,\(base64Audio)"
        
        logger.debug("Audio encoded (Base64 length: \(base64Audio.count) chars)")
        
        // Build request body according to Qwen3 ASR API spec
        var requestBody: [String: Any] = [
            "model": model ?? "qwen3-asr-flash",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_audio",
                            "input_audio": [
                                "data": dataURI
                            ]
                        ]
                    ]
                ]
            ],
            "stream": false
        ]
        
        // Add language if specified
        if let language = language, language != "auto" {
            var asrOptions: [String: Any] = [:]
            asrOptions["language"] = language
            asrOptions["enable_itn"] = false
            requestBody["extra_body"] = ["asr_options": asrOptions]
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        logger.debug("Sending request to Qwen3 ASR API...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Qwen3 ASR: Invalid response type")
            throw ASRError.invalidResponse
        }
        
        logger.debug("Qwen3 ASR API response status: \(httpResponse.statusCode)")
        
        // Log raw response for debugging
        if let rawResponse = String(data: data, encoding: .utf8) {
            logger.debug("Raw API response: \(rawResponse.prefix(500))")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Qwen3 ASR API error (\(httpResponse.statusCode)): \(errorMessage)")
            throw ASRError.serverError(httpResponse.statusCode, errorMessage)
        }
        
        // Parse response - Qwen3 uses different structure than OpenAI
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Qwen3 ASR: Failed to parse response JSON")
            throw ASRError.invalidResponse
        }
        
        // Extract text from choices[0].message.content
        var language: String? = nil
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            logger.error("Qwen3 ASR: No transcription text found in response")
            logger.error("Full JSON keys: \(json.keys.joined(separator: ", "))")
            throw ASRError.transcriptionFailed("Empty or invalid response from API")
        }
        
        // Extract language from annotations if available
        if let annotations = message["annotations"] as? [[String: Any]],
           let firstAnnotation = annotations.first,
           let lang = firstAnnotation["language"] as? String {
            language = lang
        }
        
        logger.info("Qwen3 ASR: Transcription successful (\(content.count) chars)")
        return ASRResult(
            text: content,
            language: language,
            confidence: nil,
            duration: nil
        )
    }
}
