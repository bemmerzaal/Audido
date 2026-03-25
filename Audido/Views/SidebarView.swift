import SwiftUI
import SwiftData

struct SidebarView: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @Environment(TranscriptionQueue.self) private var transcriptionQueue
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: SidebarItem?
    @State private var recordingToDelete: Recording?

    private var recentRecordings: [Recording] {
        Array(recordings.prefix(5))
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("sidebar.home", systemImage: "house")
                    .tag(SidebarItem.home)

                Label("sidebar.all_items", systemImage: "list.bullet.rectangle")
                    .badge(recordings.count)
                    .tag(SidebarItem.allItems)

                Label("sidebar.podcasts", systemImage: "apple.podcasts.pages")
                    .tag(SidebarItem.podcasts)
            }

            if transcriptionQueue.hasActiveTasks {
                Section("home.transcriptions") {
                    ForEach(transcriptionQueue.activeTasks) { task in
                        TranscriptionQueueRow(task: task)
                            .tag(SidebarItem.recording(task.recording))
                    }
                }
            }

            if !recentRecordings.isEmpty {
                Section("sidebar.recent") {
                    ForEach(recentRecordings) { recording in
                        RecordingRow(recording: recording)
                            .tag(SidebarItem.recording(recording))
                            .contextMenu {
                                Button {
                                    selection = .recording(recording)
                                } label: {
                                    Label("sidebar.open", systemImage: "arrow.up.right.square")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    recordingToDelete = recording
                                } label: {
                                    Label("sidebar.delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .alert(
            Text(String(format: String(localized: "delete.confirm_title"), recordingToDelete?.title ?? "")),
            isPresented: Binding(get: { recordingToDelete != nil }, set: { if !$0 { recordingToDelete = nil } })
        ) {
            Button("delete.confirm_button", role: .destructive) {
                if let recording = recordingToDelete {
                    if case .recording(let sel) = selection, sel.id == recording.id {
                        selection = .home
                    }
                    deleteRecording(recording)
                }
                recordingToDelete = nil
            }
            Button("delete.cancel_button", role: .cancel) {
                recordingToDelete = nil
            }
        } message: {
            Text("delete.confirm_message")
        }
    }

    private func deleteRecording(_ recording: Recording) {
        if recording.sourceType == .recording {
            try? FileManager.default.removeItem(at: recording.fileURL)
        }
        modelContext.delete(recording)
    }
}

struct TranscriptionQueueRow: View {
    @Environment(TranscriptionQueue.self) private var queue
    let task: TranscriptionTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(task.recording.title)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                if task.state == .active {
                    Text("\(Int(task.progress * 100))%")
                        .monospacedDigit()
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if task.state == .queued {
                    Text("sidebar.in_queue")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if task.state == .active {
                ProgressView(value: task.progress)
                    .progressViewStyle(.linear)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(role: .destructive) {
                queue.cancelTask(task)
            } label: {
                Label("sidebar.cancel", systemImage: "xmark.circle")
            }
        }
    }
}

struct RecordingRow: View {
    let recording: Recording
    var searchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: recording.sourceIcon)
                    .font(.body)
                    .foregroundStyle(iconColor)

                Text(recording.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Spacer()

                if recording.isTranscribing {
                    ProgressView()
                        .scaleEffect(0.6)
                } else if !recording.transcriptionText.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.callout)
                }
            }

            HStack {
                Text(recording.createdAt, style: .date)
                Text("·")
                if recording.sourceType == .recording {
                    Text(formatDuration(recording.duration))
                } else {
                    Text(recording.sourceLabel)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let snippet = transcriptionSnippet {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, 2)
    }

    // Number of characters of context shown before and after a transcription match.
    private static let snippetContextLength = 60

    // Extracts a highlighted snippet from the transcription around the first match.
    private var transcriptionSnippet: AttributedString? {
        guard !searchText.isEmpty,
              !recording.transcriptionText.isEmpty else { return nil }
        let text = recording.transcriptionText
        guard let matchRange = text.range(of: searchText, options: .caseInsensitive) else { return nil }

        // Derive snippet bounds directly from the match's String.Index values so we
        // avoid two O(text.count) distance() calls and one O(text.count) .count call.
        // index(_:offsetBy:limitedBy:) only traverses up to snippetContextLength characters.
        let siStart = text.index(matchRange.lowerBound, offsetBy: -Self.snippetContextLength,
                                 limitedBy: text.startIndex) ?? text.startIndex
        let siEnd   = text.index(matchRange.upperBound, offsetBy: Self.snippetContextLength,
                                 limitedBy: text.endIndex) ?? text.endIndex

        let prefix = siStart > text.startIndex ? "…" : ""
        let suffix = siEnd < text.endIndex ? "…" : ""

        let before  = prefix + String(text[siStart..<matchRange.lowerBound])
        let matched = String(text[matchRange])
        let after   = String(text[matchRange.upperBound..<siEnd]) + suffix

        var result = AttributedString(before)
        var highlight = AttributedString(matched)
        highlight.backgroundColor = Color.accentColor.opacity(0.25)
        // Explicitly set primary to override the parent Text's .foregroundStyle(.secondary),
        // so the highlighted word remains readable against the tinted background.
        highlight.foregroundColor = Color.primary
        result += highlight
        result += AttributedString(after)
        return result
    }

    private var iconColor: Color {
        switch recording.sourceType {
        case .recording: return .red
        case .importedFile: return .blue
        case .podcast: return .purple
        }
    }
}
