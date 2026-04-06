import Foundation

struct ASRResult {
    let text: String
    let language: String?
    let confidence: Double?
    let duration: TimeInterval?
}

protocol ASRBackend {
    var name: String { get }
    func transcribe(audioURL: URL, language: String?, model: String?) async throws -> ASRResult
}

enum ASRError: LocalizedError {
    case noAPIKey
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case serverError(Int, String)
    case audioFileError
    case transcriptionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "API key not configured"
        case .invalidURL:
            return "Invalid API URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .audioFileError:
            return "Failed to read audio file"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        }
    }
}