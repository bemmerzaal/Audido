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
    case meetingCapture
}

struct ContentView: View {
    @Environment(AudioRecorderService.self) private var audioRecorder
    @Environment(TranscriptionService.self) private var transcriptionService
    @Environment(ModelManager.self) private var modelManager
    @Environment(PodcastService.self) private var podcastService
    @Environment(AudioDeviceManager.self) private var audioDeviceManager
    @Environment(MeetingCaptureService.self) private var meetingCapture
    @Environment(\.modelContext) private var modelContext
    @State private var selection: SidebarItem? = .home
    @State private var showModelManagement = false
    @State private var showFileImporter = false
    @State private var showRecordModePopover = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 250, ideal: 310)
        } detail: {
            VStack(spacing: 0) {
                Divider()
                detailContent
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    Button {
                        showRecordModePopover = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "record.circle")
                            Text("nav.new_recording")
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .foregroundStyle(.white)
                        .background(Color.red)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(audioRecorder.isRecording || meetingCapture.isCapturing)
                    .opacity(audioRecorder.isRecording || meetingCapture.isCapturing ? 0.6 : 1)
                    .popover(isPresented: $showRecordModePopover, arrowEdge: .bottom) {
                        recordModePopover
                    }

                    Button {
                        showFileImporter = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.badge.plus")
                            Text("nav.upload_audio")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .foregroundStyle(.primary)
                        .background(Color(NSColor.windowBackgroundColor))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("nav.import_help")
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showModelManagement = true
                } label: {
                    Image(systemName: "cpu")
                }
                .help("settings.manage_models")
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
                        Button("settings.done") {
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

    // MARK: - Recording mode popover

    private var recordModePopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("nav.choose_mode")
                .font(.headline)
                .padding(.bottom, 4)

            Button {
                showRecordModePopover = false
                startRecording()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mic.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("nav.microphone")
                            .fontWeight(.medium)
                        Text("nav.microphone_subtitle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            Button {
                showRecordModePopover = false
                selection = .meetingCapture
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "video.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("sidebar.meeting_capture")
                            .fontWeight(.medium)
                        Text("nav.meeting_subtitle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Detail content

    @ViewBuilder
    private var detailContent: some View {
        if audioRecorder.isRecording {
            ActiveRecordingView(onRecordingSaved: { recording in
                selection = .recording(recording)
            })
        } else if meetingCapture.isCapturing {
            ActiveMeetingCaptureView(onCaptureSaved: { recording in
                selection = .recording(recording)
            })
        } else {
            switch selection {
            case .home, .none:
                HomeView(onStartRecording: {
                    startRecording()
                }, onSelectRecording: { recording in
                    selection = .recording(recording)
                }, onStartMeetingCapture: {
                    selection = .meetingCapture
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
            case .meetingCapture:
                MeetingCaptureSetupView(onCaptureSaved: { recording in
                    selection = .recording(recording)
                })
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
        guard url.startAccessingSecurityScopedResource() else {
            print("Could not access file: \(url)")
            return
        }

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
