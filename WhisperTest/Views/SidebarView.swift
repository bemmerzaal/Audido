import SwiftUI
import SwiftData

struct SidebarView: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @Environment(TranscriptionQueue.self) private var transcriptionQueue
    @Binding var selection: SidebarItem?

    private var recentRecordings: [Recording] {
        Array(recordings.prefix(5))
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Home", systemImage: "house")
                    .tag(SidebarItem.home)

                Label("All Items", systemImage: "list.bullet.rectangle")
                    .badge(recordings.count)
                    .tag(SidebarItem.allItems)

                Label("Search podcasts", systemImage: "apple.podcasts.pages")
                    .tag(SidebarItem.podcasts)
            }

            if transcriptionQueue.hasActiveTasks {
                Section("Transcriptions") {
                    ForEach(transcriptionQueue.activeTasks) { task in
                        TranscriptionQueueRow(task: task)
                            .tag(SidebarItem.recording(task.recording))
                    }
                }
            }

            if !recentRecordings.isEmpty {
                Section("Recents") {
                    ForEach(recentRecordings) { recording in
                        RecordingRow(recording: recording)
                            .tag(SidebarItem.recording(recording))
                    }
                }
            }
        }
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
                    Text("In wachtrij")
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
            Button("Cancel", role: .destructive) {
                queue.cancelTask(task)
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
