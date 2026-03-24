import SwiftUI
import SwiftData

struct SidebarView: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @Environment(TranscriptionQueue.self) private var transcriptionQueue
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: SidebarItem?

    private var recentRecordings: [Recording] {
        Array(recordings.prefix(5))
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Home", systemImage: "house")
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
                                    if case .recording(let sel) = selection, sel.id == recording.id {
                                        selection = .home
                                    }
                                    deleteRecording(recording)
                                } label: {
                                    Label("sidebar.delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: recording.sourceIcon)
                    .font(.caption2)
                    .foregroundStyle(iconColor)

                Text(recording.title)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                if recording.isTranscribing {
                    ProgressView()
                        .scaleEffect(0.5)
                } else if !recording.transcriptionText.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
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
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var iconColor: Color {
        switch recording.sourceType {
        case .recording: return .red
        case .importedFile: return .blue
        case .podcast: return .purple
        }
    }
}
