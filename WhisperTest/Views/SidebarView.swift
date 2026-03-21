import SwiftUI
import SwiftData

struct SidebarView: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @Binding var selection: SidebarItem?

    private var recentRecordings: [Recording] {
        Array(recordings.prefix(5))
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Home", systemImage: "house.fill")
                    .tag(SidebarItem.home)

                Label("Recordings", systemImage: "waveform")
                    .tag(SidebarItem.recordings)
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

struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
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
                Text(formatDuration(recording.duration))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
