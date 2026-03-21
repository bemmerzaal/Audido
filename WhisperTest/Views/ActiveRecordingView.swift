import SwiftUI
import SwiftData

struct ActiveRecordingView: View {
    @Environment(AudioRecorderService.self) private var audioRecorder
    @Environment(\.modelContext) private var modelContext
    var onRecordingSaved: (Recording) -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Recording indicator
            VStack(spacing: 16) {
                Image(systemName: "record.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: true)

                Text("Recording...")
                    .font(.title2)
                    .fontWeight(.medium)

                Text(formatDuration(audioRecorder.currentDuration))
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Audio level
            AudioLevelIndicator(level: audioRecorder.audioLevel, barCount: 40)
                .frame(height: 32)
                .padding(.horizontal, 48)

            // Stop button
            Button {
                stopRecording()
            } label: {
                Label("Stop Recording", systemImage: "stop.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Recording")
    }

    private func stopRecording() {
        let duration = audioRecorder.stopRecording()
        guard let fileName = audioRecorder.currentFileName else { return }
        audioRecorder.currentFileName = nil

        let recording = Recording(
            title: "Recording \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))",
            duration: duration,
            fileName: fileName
        )
        modelContext.insert(recording)
        onRecordingSaved(recording)
    }
}
