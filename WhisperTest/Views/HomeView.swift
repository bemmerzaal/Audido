import SwiftUI
import SwiftData

struct HomeView: View {
    @Query private var recordings: [Recording]
    @Environment(ModelManager.self) private var modelManager
    var onStartRecording: () -> Void
    var onSelectRecording: (Recording) -> Void

    private var transcriptionCount: Int {
        recordings.filter { !$0.transcriptionText.isEmpty }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Stats tiles
                HStack(spacing: 16) {
                    StatTile(
                        title: "Recordings",
                        value: "\(recordings.count)",
                        icon: "waveform",
                        color: .blue
                    )

                    StatTile(
                        title: "Transcriptions",
                        value: "\(transcriptionCount)",
                        icon: "text.below.photo",
                        color: .green
                    )
                }

                // New Recording widget
                Button(action: onStartRecording) {
                    VStack(spacing: 12) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.red)

                        Text("New Recording")
                            .font(.headline)

                        Text("Tap to start recording audio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                // Model status
                if modelManager.selectedModelName == nil {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("No model selected. Open Settings to download and select a Whisper model.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }
            }
            .padding(24)
        }
        .navigationTitle("Home")
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
