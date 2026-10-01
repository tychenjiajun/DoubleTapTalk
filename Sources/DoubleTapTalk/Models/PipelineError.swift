import Foundation

/// Errors thrown by the speech → polish → inject pipeline.
/// (Renamed from ASRError after the app became Apple-on-device-only.)
enum PipelineError: LocalizedError {
    case invalidResponse
    case audioFileError
    case transcriptionFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response"
        case .audioFileError:
            return "Failed to process audio"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .timeout:
            return "Operation timed out"
        }
    }
}