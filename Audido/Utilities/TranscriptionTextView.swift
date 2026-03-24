import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Reusable transcription text display with optional AI summary and action items
struct TranscriptionTextView: View {
    let text: String
    @Binding var fontSize: Double
    @Binding var summaryText: String?
    @Binding var actionItemsText: String?
    @Binding var isSummarizing: Bool
    @Binding var isExtractingActions: Bool

    @State private var summaryExpanded = true
    @State private var actionsExpanded = true
    @State private var transcriptionExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // AI Summary section
                if isSummarizing {
                    aiLoadingView(title: "AI Summary", message: "Generating summary...")
                        .padding()
                } else if let summary = summaryText {
                    collapsiblePanel(
                        title: "AI Summary",
                        icon: "apple.intelligence",
                        color: .purple,
                        content: summary,
                        isExpanded: $summaryExpanded,
                        onDismiss: { summaryText = nil } as () -> Void
                    )
                    .padding()
                }

                // Action Items section
                if isExtractingActions {
                    aiLoadingView(title: "Action Items", message: "Extracting actions...")
                        .padding()
                } else if let actions = actionItemsText {
                    collapsiblePanel(
                        title: "Action Items",
                        icon: "checklist",
                        color: .orange,
                        content: actions,
                        isExpanded: $actionsExpanded,
                        onDismiss: { actionItemsText = nil } as () -> Void
                    )
                    .padding()
                }

                // Transcription text
                collapsiblePanel(
                    title: "Transcription",
                    icon: "text.alignleft",
                    color: .secondary,
                    content: text,
                    isExpanded: $transcriptionExpanded,
                    onDismiss: nil
                )
                .padding()
            }
        }
    }

    // MARK: - Shared AI Views

    private func aiLoadingView(title: String, message: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: title == "AI Summary" ? "apple.intelligence" : "checklist")
                    .foregroundStyle(title == "AI Summary" ? .purple : .orange)
                Text(title)
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding()
        .background((title == "AI Summary" ? Color.purple : Color.orange).opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func collapsiblePanel(
        title: String,
        icon: String,
        color: Color,
        content: String,
        isExpanded: Binding<Bool>,
        onDismiss: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible, acts as toggle
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                            .frame(width: 12)

                        Image(systemName: icon)
                            .foregroundStyle(color)
                        Text(title)
                            .font(.headline)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if isExpanded.wrappedValue {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(content, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Copy \(title.lowercased())")
                }

                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss \(title.lowercased())")
                }
            }

            // Content — collapsible
            if isExpanded.wrappedValue {
                Text(content)
                    .font(.system(size: fontSize))
                    .textSelection(.enabled)
                    .padding(.top, 8)
            }
        }
        .padding()
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
