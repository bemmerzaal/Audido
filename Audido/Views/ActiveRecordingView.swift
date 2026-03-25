import SwiftUI
import SwiftData

struct ActiveRecordingView: View {
    @Environment(AudioRecorderService.self) private var audioRecorder
    @Environment(\.modelContext) private var modelContext
    var onRecordingSaved: (Recording) -> Void
    @State private var isStopping = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            WaveformPill(
                level: audioRecorder.audioLevel,
                duration: audioRecorder.currentDuration
            )

            Button {
                guard !isStopping else { return }
                isStopping = true
                stopRecording()
            } label: {
                Label(isStopping ? LocalizedStringKey("recording.stopping") : LocalizedStringKey("recording.stop"), systemImage: "stop.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(isStopping)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(Text("recording.recording"))
    }

    private func stopRecording() {
        let duration = audioRecorder.stopRecording()
        guard let fileName = audioRecorder.currentFileName else {
            isStopping = false
            return
        }
        audioRecorder.currentFileName = nil

        let recording = Recording(
            title: "\(String(localized: "recording.title_prefix")) \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))",
            duration: duration,
            fileName: fileName
        )
        modelContext.insert(recording)
        onRecordingSaved(recording)
    }
}
