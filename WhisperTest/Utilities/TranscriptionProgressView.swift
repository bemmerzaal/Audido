import SwiftUI

struct TranscriptionProgressView: View {
    @Environment(TranscriptionService.self) private var transcriptionService

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: transcriptionService.transcriptionProgress)
                .progressViewStyle(.linear)
                .frame(width: 300)

            // Status text
            if transcriptionService.isPaused {
                Text("Paused at \(Int(transcriptionService.transcriptionProgress * 100))%")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else {
                Text(transcriptionService.statusMessage ?? "Transcribing...")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            // Control buttons
            HStack(spacing: 12) {
                if transcriptionService.isPaused {
                    Button {
                        transcriptionService.resumeTranscription()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        transcriptionService.pauseTranscription()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive) {
                    transcriptionService.cancelTranscription()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
