import Foundation
import WhisperKit
import Observation

enum TranscriptionError: LocalizedError {
    case noModelLoaded

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "No transcription model is loaded. Please download and select a model in Settings."
        }
    }
}

@Observable
final class TranscriptionService {
    var isModelLoaded = false
    private var whisperKit: WhisperKit?

    func loadModel(from folder: String) async throws {
        whisperKit = try await WhisperKit(modelFolder: folder)
        isModelLoaded = true
    }

    func transcribe(audioURL: URL, language: String = "nl") async throws -> String {
        guard let whisperKit else { throw TranscriptionError.noModelLoaded }

        let options = DecodingOptions(
            language: language == "auto" ? nil : language
        )

        let results = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: options)
        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    func unloadModel() {
        whisperKit = nil
        isModelLoaded = false
    }
}
