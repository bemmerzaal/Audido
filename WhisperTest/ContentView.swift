import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
    case home
    case allItems
    case recording(Recording)
    case podcasts
    case podcastDetail(Podcast)
    case podcastEpisode(Podcast, PodcastEpisode)
    case importedFile(URL)
}

struct ContentView: View {
    @Environment(AudioRecorderService.self) private var audioRecorder
    @Environment(TranscriptionService.self) private var transcriptionService
    @Environment(ModelManager.self) private var modelManager
    @Environment(PodcastService.self) private var podcastService
    @Environment(AudioDeviceManager.self) private var audioDeviceManager
    @Environment(\.modelContext) private var modelContext
    @State private var selection: SidebarItem? = .home
    @State private var showModelManagement = false
    @State private var showFileImporter = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            detailContent
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    startRecording()
                } label: {
                    Label("Record", systemImage: "record.circle")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(audioRecorder.isRecording)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Import Audio", systemImage: "doc.badge.plus")
                }
                .help("Import an audio file (MP3, M4A, WAV, etc.)")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showModelManagement = true
                } label: {
                    Label("Models", systemImage: "cpu")
                }
                .help("Manage Whisper models")
            }
        }
        .sheet(isPresented: $showModelManagement) {
            ModelManagementView()
                .environment(modelManager)
                .environment(transcriptionService)
                .environment(audioDeviceManager)
                .frame(minWidth: 500, minHeight: 450)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showModelManagement = false
                        }
                    }
                }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav, .aiff],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    handleImportedFile(url)
                }
            case .failure(let error):
                print("File import failed: \(error)")
            }
        }
        .onChange(of: selection) { oldValue, newValue in
            print("[NAV] Selection changed: \(String(describing: oldValue)) → \(String(describing: newValue))")
        }
        .task {
            if let folder = modelManager.selectedModelFolder {
                try? await transcriptionService.loadModel(from: folder)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if audioRecorder.isRecording {
            ActiveRecordingView(onRecordingSaved: { recording in
                selection = .recording(recording)
            })
        } else {
            switch selection {
            case .home, .none:
                HomeView(onStartRecording: {
                    startRecording()
                }, onSelectRecording: { recording in
                    selection = .recording(recording)
                })
            case .allItems:
                RecordingsListView(onSelectRecording: { recording in
                    selection = .recording(recording)
                })
            case .recording(let recording):
                RecordingDetailView(recording: recording)
            case .podcasts:
                PodcastSearchView(onSelectPodcast: { podcast in
                    selection = .podcastDetail(podcast)
                })
            case .podcastDetail(let podcast):
                PodcastEpisodeListView(podcast: podcast, onSelectEpisode: { episode in
                    selection = .podcastEpisode(podcast, episode)
                }, onBack: {
                    selection = .podcasts
                })
            case .podcastEpisode(let podcast, let episode):
                PodcastEpisodeDetailView(episode: episode, podcast: podcast)
            case .importedFile(let url):
                ImportedFileView(fileURL: url)
            }
        }
    }

    private func startRecording() {
        let fileName = "recording-\(UUID().uuidString).wav"
        let fileURL = Recording.recordingsDirectory.appendingPathComponent(fileName)
        do {
            try audioRecorder.startRecording(to: fileURL, inputDeviceID: audioDeviceManager.resolvedDeviceID)
            audioRecorder.currentFileName = fileName
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    private func handleImportedFile(_ url: URL) {
        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            print("Could not access file: \(url)")
            return
        }

        // Copy file to app's documents to avoid sandbox issues
        let importDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: importDir, withIntermediateDirectories: true)

        let destURL = importDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: destURL)

        do {
            try FileManager.default.copyItem(at: url, to: destURL)
            url.stopAccessingSecurityScopedResource()
            selection = .importedFile(destURL)
        } catch {
            url.stopAccessingSecurityScopedResource()
            print("Failed to copy imported file: \(error)")
        }
    }
}
