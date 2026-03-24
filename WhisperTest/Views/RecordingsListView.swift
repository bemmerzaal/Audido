import SwiftUI
import SwiftData

struct RecordingsListView: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var filterType: FilterType = .all
    @State private var selectedRecording: Recording?
    @State private var showPanel = true
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
                ($0.podcastName ?? "").localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) }) ||
                $0.notes.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    private var allTags: [String] {
        Array(Set(recordings.flatMap { $0.tags })).sorted()
    }

    private var panelVisible: Bool {
        selectedRecording != nil && showPanel
    }

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - List column
            VStack(alignment: .leading, spacing: 0) {
                // Search + filter bar — always anchored at top
                HStack(spacing: 12) {
                    Picker("Filter", selection: $filterType) {
                        ForEach(FilterType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    Spacer()

                    // Inline search field
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        TextField("Zoeken...", text: $searchText)
                            .textFieldStyle(.plain)
                            .frame(width: 220)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
                }
                .padding()

                Divider()

                // Content area
                if recordings.isEmpty {
                    ContentUnavailableView(
                        "No Items Yet",
                        systemImage: "tray",
                        description: Text("Record audio, import a file, or transcribe a podcast to get started.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredRecordings.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(filteredRecordings) { recording in
                                Button {
                                    selectedRecording = recording
                                    showPanel = true
                                } label: {
                                    RecordingRow(recording: recording)
                                        .padding(.horizontal)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .background(
                                            selectedRecording?.id == recording.id && showPanel
                                                ? Color.accentColor.opacity(0.1)
                                                : Color.clear
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        onSelectRecording(recording)
                                    } label: {
                                        Label("Open", systemImage: "arrow.up.right.square")
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        if selectedRecording?.id == recording.id {
                                            selectedRecording = nil
                                        }
                                        deleteRecording(recording)
                                    } label: {
                                        Label("Verwijder", systemImage: "trash")
                                    }
                                }

                                Divider()
                                    .padding(.leading)
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 280, maxHeight: .infinity, alignment: .top)

            // MARK: - Quick look panel
            if let selected = selectedRecording, showPanel {
                Divider()
                RecordingQuickLookPanel(
                    recording: selected,
                    allTags: allTags,
                    onOpenFull: { onSelectRecording(selected) },
                    onClose: { withAnimation(.easeInOut(duration: 0.2)) { showPanel = false } }
                )
                .frame(width: 340)
                .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("All Items")
        .onChange(of: recordings) {
            if let sel = selectedRecording, !recordings.contains(where: { $0.id == sel.id }) {
                selectedRecording = nil
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
