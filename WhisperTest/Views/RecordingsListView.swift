import SwiftUI
import SwiftData

struct RecordingsListView: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var filterType: FilterType = .all
    var onSelectRecording: (Recording) -> Void

    enum FilterType: String, CaseIterable {
        case all = "All"
        case recording = "Recordings"
        case importedFile = "Imports"
        case podcast = "Podcasts"
    }

    private var filteredRecordings: [Recording] {
        var result = recordings

        // Filter by type
        switch filterType {
        case .all: break
        case .recording: result = result.filter { $0.sourceType == .recording }
        case .importedFile: result = result.filter { $0.sourceType == .importedFile }
        case .podcast: result = result.filter { $0.sourceType == .podcast }
        }

        // Filter by search text
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.transcriptionText.localizedCaseInsensitiveContains(searchText) ||
                ($0.podcastName ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    var body: some View {
        List {
            // Filter bar
            Picker("Filter", selection: $filterType) {
                ForEach(FilterType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if filteredRecordings.isEmpty {
                ContentUnavailableView(
                    recordings.isEmpty ? "No Items" : "No Results",
                    systemImage: recordings.isEmpty ? "tray" : "magnifyingglass",
                    description: Text(recordings.isEmpty
                        ? "Record audio, import a file, or transcribe a podcast to get started."
                        : "No items match your search or filter.")
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
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
        }
        .searchable(text: $searchText, prompt: "Search recordings, podcasts, imports...")
        .navigationTitle("All Items")
    }

    private func deleteRecording(_ recording: Recording) {
        // Only delete the audio file if it's a recording (not shared podcast/import files)
        if recording.sourceType == .recording {
            try? FileManager.default.removeItem(at: recording.fileURL)
        }
        modelContext.delete(recording)
    }
}
