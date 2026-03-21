import SwiftUI
import SwiftData

struct RecordingControlsView: View {
    @Environment(AudioRecorderService.self) private var audioRecorder
    @Environment(TranscriptionService.self) private var transcriptionService
    @Environment(ModelManager.self) private var modelManager
    @Environment(\.modelContext) private var modelContext
    @State private var currentFileName: String?

    var body: some View {
        HStack(spacing: 12) {
            if audioRecorder.isRecording {
                AudioLevelIndicator(level: audioRecorder.audioLevel)

                Text(formatDuration(audioRecorder.currentDuration))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Button {
                    stopRecording()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    startRecording()
                } label: {
                    Label("Record", systemImage: "record.circle")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }

    private func startRecording() {
        let fileName = "recording-\(UUID().uuidString).wav"
        currentFileName = fileName
        let fileURL = Recording.recordingsDirectory.appendingPathComponent(fileName)

        do {
            try audioRecorder.startRecording(to: fileURL)
        } catch {
            print("Failed to start recording: \(error)")
            currentFileName = nil
        }
    }

    private func stopRecording() {
        let duration = audioRecorder.stopRecording()
        guard let fileName = currentFileName else { return }
        currentFileName = nil

        let recording = Recording(
            title: "Recording \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))",
            duration: duration,
            fileName: fileName
        )
        modelContext.insert(recording)

        if transcriptionService.isModelLoaded {
            Task {
                recording.isTranscribing = true
                do {
                    let text = try await transcriptionService.transcribe(audioURL: recording.fileURL, language: modelManager.selectedLanguage)
                    recording.transcriptionText = text
                } catch {
                    print("Transcription failed: \(error)")
                }
                recording.isTranscribing = false
            }
        }
    }
}
