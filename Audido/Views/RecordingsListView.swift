import SwiftUI
import SwiftData

struct RecordingsListView: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var filterType: FilterType = .all
    @State private var selectedRecording: Recording?
    @State private var showPanel = true
    @State private var recordingToDelete: Recording?
    @State private var isSelectMode = false
    @State private var selectedIDs = Set<PersistentIdentifier>()
    @State private var showBulkDeleteConfirm = false
    var onSelectRecording: (Recording) -> Void

    enum FilterType: String, CaseIterable {
        case all
        case recording
        case importedFile
        case podcast

        var titleKey: LocalizedStringKey {
            switch self {
            case .all: return "list.filter.all"
            case .recording: return "list.filter.recordings"
            case .importedFile: return "list.filter.imports"
            case .podcast: return "list.filter.podcasts"
            }
        }
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
                HStack(spacing: 10) {
                    // 1. Select / Done button — uiterst links
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSelectMode.toggle()
                            if !isSelectMode { selectedIDs.removeAll() }
                        }
                    } label: {
                        Text(isSelectMode ? LocalizedStringKey("settings.done") : LocalizedStringKey("list.select"))
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color(NSColor.separatorColor), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    if !isSelectMode {
                        // 2. Segmented filter (label komt van de Picker)
                        Picker("list.filter", selection: $filterType) {
                            ForEach(FilterType.allCases, id: \.self) { type in
                                Text(type.titleKey).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    } else {
                        // In selectiemodus: selecteer-alles knop
                        Button {
                            if selectedIDs.count == filteredRecordings.count {
                                selectedIDs.removeAll()
                            } else {
                                selectedIDs = Set(filteredRecordings.map { $0.persistentModelID })
                            }
                        } label: {
                            Text(selectedIDs.count == filteredRecordings.count
                                 ? LocalizedStringKey("list.deselect_all")
                                 : LocalizedStringKey("list.select_all"))
                                .font(.callout)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color(NSColor.separatorColor), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Search field — alleen buiten selectiemodus
                    if !isSelectMode {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                            TextField("list.search_placeholder", text: $searchText)
                                .textFieldStyle(.plain)
                                .frame(width: 180)
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
                        .padding(.vertical, 6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
                    }
                }
                .padding()

                Divider()

                // Content area
                if recordings.isEmpty {
                    ContentUnavailableView(
                        "list.empty_title",
                        systemImage: "tray",
                        description: Text("list.empty_description")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredRecordings.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredRecordings) { recording in
                                let isChecked = selectedIDs.contains(recording.persistentModelID)
                                Button {
                                    if isSelectMode {
                                        if isChecked {
                                            selectedIDs.remove(recording.persistentModelID)
                                        } else {
                                            selectedIDs.insert(recording.persistentModelID)
                                        }
                                    } else {
                                        selectedRecording = recording
                                        showPanel = true
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        if isSelectMode {
                                            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                                                .transition(.scale.combined(with: .opacity))
                                        }
                                        RecordingRow(recording: recording)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(RoundedRectangle(cornerRadius: 12))
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(isChecked
                                                ? Color.accentColor.opacity(0.10)
                                                : (selectedRecording?.id == recording.id && showPanel && !isSelectMode
                                                    ? Color.accentColor.opacity(0.08)
                                                    : Color(NSColor.controlBackgroundColor)))
                                            .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(
                                                isChecked
                                                    ? Color.accentColor.opacity(0.5)
                                                    : (selectedRecording?.id == recording.id && showPanel && !isSelectMode
                                                        ? Color.accentColor.opacity(0.4)
                                                        : Color(NSColor.separatorColor).opacity(0.4)),
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if !isSelectMode {
                                        Button {
                                            onSelectRecording(recording)
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    // Bulk delete bar
                    if isSelectMode {
                        Divider()
                        HStack {
                            Text(selectedIDs.isEmpty
                                ? "Niets geselecteerd"
                                : "\(selectedIDs.count) geselecteerd")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                showBulkDeleteConfirm = true
                            } label: {
                                Label("Verwijder \(selectedIDs.count)", systemImage: "trash")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.small)
                            .disabled(selectedIDs.isEmpty)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
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
        .navigationTitle("sidebar.all_items")
        .onChange(of: recordings) {
            if let sel = selectedRecording, !recordings.contains(where: { $0.id == sel.id }) {
                selectedRecording = nil
            }
        }
        // Single delete confirmation
        .alert(
            Text(String(format: String(localized: "delete.confirm_title"), recordingToDelete?.title ?? "")),
            isPresented: Binding(get: { recordingToDelete != nil }, set: { if !$0 { recordingToDelete = nil } })
        ) {
            Button("delete.confirm_button", role: .destructive) {
                if let recording = recordingToDelete {
                    if selectedRecording?.id == recording.id { selectedRecording = nil }
                    deleteRecording(recording)
                }
                recordingToDelete = nil
            }
            Button("delete.cancel_button", role: .cancel) { recordingToDelete = nil }
        } message: {
            Text("delete.confirm_message")
        }
        // Bulk delete confirmation
        .alert(
            Text("\(selectedIDs.count) opnames verwijderen?"),
            isPresented: $showBulkDeleteConfirm
        ) {
            Button("delete.confirm_button", role: .destructive) {
                let toDelete = recordings.filter { selectedIDs.contains($0.persistentModelID) }
                if let sel = selectedRecording, toDelete.contains(where: { $0.id == sel.id }) {
                    selectedRecording = nil
                }
                toDelete.forEach { deleteRecording($0) }
                selectedIDs.removeAll()
                isSelectMode = false
            }
            Button("delete.cancel_button", role: .cancel) {}
        } message: {
            Text("Dit kan niet ongedaan worden gemaakt.")
        }
    }

    private func deleteRecording(_ recording: Recording) {
        if recording.sourceType == .recording {
            try? FileManager.default.removeItem(at: recording.fileURL)
        }
        modelContext.delete(recording)
    }
}
