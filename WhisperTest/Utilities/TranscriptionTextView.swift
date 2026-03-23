import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Reusable transcription text display with optional AI summary
struct TranscriptionTextView: View {
    let text: String
    @Binding var fontSize: Double
    @Binding var summaryText: String?
    @Binding var isSummarizing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // AI Summary section (shown above transcription)
                if isSummarizing {
                    summaryLoadingView
                        .padding()
                } else if let summary = summaryText {
                    summaryView(summary)
                        .padding()
                }

                // Transcription text
                Text(text)
                    .font(.system(size: fontSize))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: text) {
            // Reset summary when text changes (different transcription)
            summaryText = nil
            isSummarizing = false
        }
    }

    // MARK: - Summary Views

    private var summaryLoadingView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "apple.intelligence")
                    .foregroundStyle(.purple)
                Text("AI Summary")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Generating summary...")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding()
        .background(.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func summaryView(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "apple.intelligence")
                    .foregroundStyle(.purple)
                Text("AI Summary")
                    .font(.headline)
                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summary, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Copy summary")

                Button {
                    summaryText = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss summary")
            }

            Text(summary)
                .font(.system(size: fontSize))
                .textSelection(.enabled)
        }
        .padding()
        .background(.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
