import SwiftUI
import SwiftData

struct SidebarView: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedRecording: Recording?
    @State private var searchText = ""

    private var filteredRecordings: [Recording] {
        if searchText.isEmpty {
            return recordings
        }
        return recordings.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.transcriptionText.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(filteredRecordings, selection: $selectedRecording) { recording in
            RecordingRow(recording: recording)
                .tag(recording)
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        deleteRecording(recording)
                    }
                }
        }
        .searchable(text: $searchText, prompt: "Search recordings")
        .overlay {
            if recordings.isEmpty {
                ContentUnavailableView(
                    "No Recordings",
                    systemImage: "waveform",
                    description: Text("Press Record to start your first recording.")
                )
            } else if filteredRecordings.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func deleteRecording(_ recording: Recording) {
        try? FileManager.default.removeItem(at: recording.fileURL)
        if selectedRecording == recording {
            selectedRecording = nil
        }
        modelContext.delete(recording)
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
