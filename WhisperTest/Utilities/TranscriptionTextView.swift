import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Reusable transcription text display with inspector panel for font size and copy
struct TranscriptionTextView: View {
    let text: String
    @Environment(SummaryService.self) private var summaryService
    @Environment(ModelManager.self) private var modelManager
    @State private var fontSize: Double = 14
    @State private var showInspector = true
    @State private var copied = false
    @State private var showUnavailableAlert = false
    @State private var summaryText: String?
    @State private var isSummarizing = false

    var body: some View {
        HStack(spacing: 0) {
            // Main text area
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

            if showInspector {
                Divider()

                // Inspector panel
                inspectorPanel
                    .frame(width: 200)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation { showInspector.toggle() }
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Toggle inspector panel")
            }
        }
        .alert("AI Summarize Not Available", isPresented: $showUnavailableAlert) {
            Button("OK") {}
        } message: {
            Text(summaryService.unavailableReason ?? "Apple Intelligence is not available on this device.")
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

    // MARK: - Inspector Panel

    private var inspectorPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Options")
                .font(.headline)

            // AI Summarize button
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Summary")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    if summaryService.isAvailable {
                        Task {
                            isSummarizing = true
                            summaryText = nil
                            await summaryService.summarize(
                                text: text,
                                language: modelManager.selectedLanguage
                            )
                            summaryText = summaryService.summaryText
                            isSummarizing = false
                        }
                    } else {
                        showUnavailableAlert = true
                    }
                } label: {
                    Label("AI Summarize", systemImage: "apple.intelligence")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(isSummarizing)
            }

            Divider()

            // Font size
            VStack(alignment: .leading, spacing: 8) {
                Text("Font Size")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Image(systemName: "textformat.size.smaller")
                        .foregroundStyle(.secondary)
                    Slider(value: $fontSize, in: 10...28, step: 1)
                    Image(systemName: "textformat.size.larger")
                        .foregroundStyle(.secondary)
                }

                Text("\(Int(fontSize)) pt")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Divider()

            // Copy button
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copied = false
                }
            } label: {
                Label(copied ? "Copied!" : "Copy Text", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            // Export button
            Button {
                exportToFile()
            } label: {
                Label("Export as TXT", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Divider()

            // Word count info
            VStack(alignment: .leading, spacing: 4) {
                Text("Statistics")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                let words = text.split(separator: " ").count
                let chars = text.count

                HStack {
                    Text("Words:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(words)")
                        .monospacedDigit()
                }
                .font(.caption)

                HStack {
                    Text("Characters:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(chars)")
                        .monospacedDigit()
                }
                .font(.caption)
            }

            Spacer()
        }
        .padding()
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "transcription.txt"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            var exportText = ""
            if let summary = summaryText {
                exportText += "=== AI SUMMARY ===\n\(summary)\n\n=== TRANSCRIPTION ===\n"
            }
            exportText += text
            try? exportText.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
