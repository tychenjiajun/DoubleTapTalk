import Foundation

struct LocalWhisperBackend: ASRBackend {
    let name = "Local Whisper"
    private let apiURL: String
    private let logger = FileLogger.shared
    
    init(apiURL: String) {
        self.apiURL = apiURL
    }
    
    func transcribe(audioURL: URL, language: String?, model: String?) async throws -> ASRResult {
        logger.info("Local Whisper: Starting transcription")
        logger.debug("Local API URL: \(apiURL)")
        logger.debug("Model: \(model ?? "default"), Language: \(language ?? "auto")")
        
        guard let url = URL(string: apiURL) else {
            logger.error("Local Whisper: Invalid API URL: \(apiURL)")
            throw ASRError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Build multipart form data
        var body = Data()
        
        // Model field (if provided)
        if let model = model {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(model)\r\n".data(using: .utf8)!)
        }
        
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
        logger.debug("Sending request to local whisper.cpp server...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Local Whisper: Invalid response type")
            throw ASRError.invalidResponse
        }
        
        logger.debug("Local whisper.cpp response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Local whisper.cpp error (\(httpResponse.statusCode)): \(errorMessage)")
            throw ASRError.serverError(httpResponse.statusCode, errorMessage)
        }
        
        // Try to parse JSON response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            logger.info("Local Whisper: Transcription successful (\(text.count) chars)")
            return ASRResult(
                text: text,
                language: json["language"] as? String,
                confidence: nil,
                duration: nil
            )
        }
        
        // If not JSON, assume plain text response
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            logger.info("Local Whisper: Transcription successful (plain text, \(text.count) chars)")
            return ASRResult(text: text, language: nil, confidence: nil, duration: nil)
        }
        
        logger.error("Local Whisper: Failed to parse response")
        throw ASRError.invalidResponse
    }
}