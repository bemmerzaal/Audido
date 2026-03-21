import SwiftUI
import SwiftData

struct RecordingsListView: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    var onSelectRecording: (Recording) -> Void

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
        List {
            ForEach(filteredRecordings) { recording in
                Button {
                    onSelectRecording(recording)
                } label: {
                    RecordingRow(recording: recording)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        deleteRecording(recording)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search recordings")
        .navigationTitle("Recordings")
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
        modelContext.delete(recording)
    }
}
