import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case home
    case recordings
    case recording(Recording)
}

struct ContentView: View {
    @Environment(AudioRecorderService.self) private var audioRecorder
    @Environment(TranscriptionService.self) private var transcriptionService
    @Environment(ModelManager.self) private var modelManager
    @State private var selection: SidebarItem? = .home
    @State private var showModelManagement = false

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
                .frame(minWidth: 500, minHeight: 450)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showModelManagement = false
                        }
                    }
                }
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
            case .recordings:
                RecordingsListView(onSelectRecording: { recording in
                    selection = .recording(recording)
                })
            case .recording(let recording):
                RecordingDetailView(recording: recording)
            }
        }
    }

    private func startRecording() {
        let fileName = "recording-\(UUID().uuidString).wav"
        let fileURL = Recording.recordingsDirectory.appendingPathComponent(fileName)
        do {
            try audioRecorder.startRecording(to: fileURL)
            audioRecorder.currentFileName = fileName
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
}
