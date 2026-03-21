import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AudioRecorderService.self) private var audioRecorder
    @Environment(TranscriptionService.self) private var transcriptionService
    @Environment(ModelManager.self) private var modelManager
    @State private var selectedRecording: Recording?
    @State private var showModelManagement = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedRecording: $selectedRecording)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            if let selectedRecording {
                RecordingDetailView(recording: selectedRecording)
            } else if modelManager.selectedModelName == nil {
                ContentUnavailableView {
                    Label("No Model Selected", systemImage: "arrow.down.circle")
                } description: {
                    Text("Download and select a Whisper model to start transcribing.")
                } actions: {
                    Button("Open Model Manager") {
                        showModelManagement = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView(
                    "Select a Recording",
                    systemImage: "waveform",
                    description: Text("Choose a recording from the sidebar or start a new one.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                RecordingControlsView()
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
}
