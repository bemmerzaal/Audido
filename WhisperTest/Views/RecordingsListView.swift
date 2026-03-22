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

        switch filterType {
        case .all: break
        case .recording: result = result.filter { $0.sourceType == .recording }
        case .importedFile: result = result.filter { $0.sourceType == .importedFile }
        case .podcast: result = result.filter { $0.sourceType == .podcast }
        }

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
        VStack(spacing: 0) {
            // Filter bar
            Picker("Filter", selection: $filterType) {
                ForEach(FilterType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Content
            if recordings.isEmpty {
                ContentUnavailableView(
                    "No Items Yet",
                    systemImage: "tray",
                    description: Text("Record audio, import a file, or transcribe a podcast to get started.")
                )
            } else if filteredRecordings.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredRecordings) { recording in
                            Button {
                                onSelectRecording(recording)
                            } label: {
                                RecordingRow(recording: recording)
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    deleteRecording(recording)
                                }
                            }

                            Divider()
                                .padding(.leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("All Items")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search...")
    }

    private func deleteRecording(_ recording: Recording) {
        if recording.sourceType == .recording {
            try? FileManager.default.removeItem(at: recording.fileURL)
        }
        modelContext.delete(recording)
    }
}
