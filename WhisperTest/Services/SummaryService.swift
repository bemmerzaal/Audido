import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

@Observable
final class SummaryService {
    var isSummarizing = false
    var summaryText: String?
    var errorMessage: String?

    /// Check if Apple Foundation Models are available on this device
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Get detailed unavailability reason
    var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return "This Mac does not support Apple Intelligence. An Apple Silicon Mac (M1 or later) is required."
                case .appleIntelligenceNotEnabled:
                    return "Apple Intelligence is not enabled. Go to System Settings → Apple Intelligence & Siri to enable it."
                case .modelNotReady:
                    return "The AI model is still downloading or preparing. Please try again later."
                @unknown default:
                    return "Apple Intelligence is not available on this device."
                }
            @unknown default:
                return "Apple Intelligence is not available."
            }
        }
        #endif
        return "AI Summarize requires macOS 26 (Tahoe) or later with Apple Silicon."
    }

    func summarize(text: String, language: String = "nl") async {
        guard !text.isEmpty else { return }

        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            guard isAvailable else {
                errorMessage = unavailableReason
                return
            }

            isSummarizing = true
            errorMessage = nil

            do {
                let session = LanguageModelSession()

                let languageName = languageDisplayName(for: language)
                let prompt = """
                Summarize the following transcription in a clear, concise summary. \
                Write the summary in \(languageName). \
                Use bullet points for key topics discussed. \
                Keep it under 200 words.

                Transcription:
                \(text)
                """

                let response = try await session.respond(to: prompt)
                await MainActor.run {
                    summaryText = response.content
                    isSummarizing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Summarization failed: \(error.localizedDescription)"
                    isSummarizing = false
                }
            }
        } else {
            errorMessage = unavailableReason
        }
        #else
        errorMessage = unavailableReason
        #endif
    }

    func clearSummary() {
        summaryText = nil
        errorMessage = nil
    }

    private func languageDisplayName(for code: String) -> String {
        let names: [String: String] = [
            "nl": "Dutch",
            "en": "English",
            "de": "German",
            "fr": "French",
            "es": "Spanish",
            "it": "Italian",
            "pt": "Portuguese",
            "ja": "Japanese",
            "ko": "Korean",
            "zh": "Chinese",
            "auto": "the same language as the transcription"
        ]
        return names[code] ?? "the same language as the transcription"
    }
}
