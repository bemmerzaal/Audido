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

    /// Maximum characters to send in a single prompt to avoid exceeding the on-device model's context window.
    private static let maxChunkSize = 12000

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
                let languageName = languageDisplayName(for: language)
                let result: String

                if text.count <= Self.maxChunkSize {
                    result = try await summarizeChunk(text: text, languageName: languageName)
                } else {
                    // Split into chunks, summarize each, then combine summaries
                    let chunks = splitIntoChunks(text: text, maxSize: Self.maxChunkSize)
                    var chunkSummaries: [String] = []

                    for (index, chunk) in chunks.enumerated() {
                        await MainActor.run {
                            summaryText = nil
                        }
                        let summary = try await summarizeChunk(
                            text: chunk,
                            languageName: languageName,
                            chunkInfo: "part \(index + 1) of \(chunks.count)"
                        )
                        chunkSummaries.append(summary)
                    }

                    // Final pass: combine chunk summaries into one
                    let combined = chunkSummaries.joined(separator: "\n\n")
                    result = try await summarizeCombined(summaries: combined, languageName: languageName)
                }

                await MainActor.run {
                    summaryText = result
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

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private func summarizeChunk(text: String, languageName: String, chunkInfo: String? = nil) async throws -> String {
        let session = LanguageModelSession()
        let chunkNote = chunkInfo.map { " This is \($0) of a longer transcription." } ?? ""
        let prompt = """
        Summarize the following transcription in a clear, concise summary. \
        Write the summary in \(languageName). \
        Use bullet points for key topics discussed. \
        Keep it under 200 words.\(chunkNote)

        Transcription:
        \(text)
        """
        let response = try await session.respond(to: prompt)
        return response.content
    }

    @available(macOS 26, *)
    private func summarizeCombined(summaries: String, languageName: String) async throws -> String {
        let session = LanguageModelSession()
        let prompt = """
        The following are summaries of different parts of one transcription. \
        Combine them into a single coherent summary in \(languageName). \
        Use bullet points for key topics discussed. \
        Keep it under 300 words.

        Partial summaries:
        \(summaries)
        """
        let response = try await session.respond(to: prompt)
        return response.content
    }
    #endif

    private func splitIntoChunks(text: String, maxSize: Int) -> [String] {
        var chunks: [String] = []
        var remaining = text[...]

        while !remaining.isEmpty {
            if remaining.count <= maxSize {
                chunks.append(String(remaining))
                break
            }

            // Try to split at a sentence boundary near maxSize
            let endIndex = remaining.index(remaining.startIndex, offsetBy: maxSize)
            let searchRange = remaining.index(endIndex, offsetBy: -200, limitedBy: remaining.startIndex) ?? remaining.startIndex
            let candidate = remaining[searchRange..<endIndex]

            if let lastPeriod = candidate.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
                let splitPoint = remaining.index(after: lastPeriod)
                chunks.append(String(remaining[remaining.startIndex..<splitPoint]).trimmingCharacters(in: .whitespacesAndNewlines))
                remaining = remaining[splitPoint...]
            } else {
                // No sentence boundary found, split at maxSize
                chunks.append(String(remaining[remaining.startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines))
                remaining = remaining[endIndex...]
            }
        }

        return chunks
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
