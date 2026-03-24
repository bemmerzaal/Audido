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
                    aiLoadingView(isSummary: true)
                        .padding()
                } else if let summary = summaryText {
                    collapsiblePanel(
                        title: "transcription.ai_summary",
                        icon: "apple.intelligence",
                        color: .purple,
                        content: summary,
                        isExpanded: $summaryExpanded,
                        copyHelp: "transcription.help_copy_summary",
                        dismissHelp: "transcription.dismiss_summary",
                        onDismiss: { summaryText = nil }
                    )
                    .padding()
                }

                // Action Items section
                if isExtractingActions {
                    aiLoadingView(isSummary: false)
                        .padding()
                } else if let actions = actionItemsText {
                    collapsiblePanel(
                        title: "transcription.action_items",
                        icon: "checklist",
                        color: .orange,
                        content: actions,
                        isExpanded: $actionsExpanded,
                        copyHelp: "transcription.help_copy_actions",
                        dismissHelp: "transcription.dismiss_actions",
                        onDismiss: { actionItemsText = nil }
                    )
                    .padding()
                }

                // Transcription text
                collapsiblePanel(
                    title: "transcription.panel_transcription",
                    icon: "text.alignleft",
                    color: .secondary,
                    content: text,
                    isExpanded: $transcriptionExpanded,
                    copyHelp: "transcription.help_copy_transcription",
                    dismissHelp: nil,
                    onDismiss: nil
                )
                .padding()
            }
        }
    }

    // MARK: - Shared AI Views

    private func aiLoadingView(isSummary: Bool) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: isSummary ? "apple.intelligence" : "checklist")
                    .foregroundStyle(isSummary ? .purple : .orange)
                Text(isSummary ? "transcription.ai_summary" : "transcription.action_items")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(isSummary ? "transcription.generating_summary" : "transcription.extracting_actions")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding()
        .background((isSummary ? Color.purple : Color.orange).opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func collapsiblePanel(
        title: LocalizedStringKey,
        icon: String,
        color: Color,
        content: String,
        isExpanded: Binding<Bool>,
        copyHelp: LocalizedStringKey,
        dismissHelp: LocalizedStringKey?,
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
                    .help(copyHelp)
                }

                if let onDismiss, let dismissHelp {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(dismissHelp)
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
