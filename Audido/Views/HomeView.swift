import SwiftUI
import SwiftData

struct HomeView: View {
    @Query private var recordings: [Recording]
    @Environment(ModelManager.self) private var modelManager
    var onStartRecording: () -> Void
    var onSelectRecording: (Recording) -> Void
    var onStartMeetingCapture: () -> Void

    private var transcriptionCount: Int {
        recordings.filter { !$0.transcriptionText.isEmpty }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Stats tiles
                HStack(spacing: 16) {
                    StatTile(
                        title: "home.recordings",
                        value: "\(recordings.count)",
                        icon: "waveform",
                        color: .blue
                    )

                    StatTile(
                        title: "home.transcriptions",
                        value: "\(transcriptionCount)",
                        icon: "text.below.photo",
                        color: .green
                    )
                }

                // Action tiles
                HStack(spacing: 16) {
                    // New Recording
                    Button(action: onStartRecording) {
                        VStack(spacing: 12) {
                            Image(systemName: "mic.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.red)

                            Text("home.record")
                                .font(.headline)

                            Text("home.microphone_recording")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)

                    // Meeting Capture
                    Button(action: onStartMeetingCapture) {
                        VStack(spacing: 12) {
                            Image(systemName: "video.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.blue)

                            Text("home.meeting")
                                .font(.headline)

                            Text("home.capture_system_audio")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }

                // Model status
                if modelManager.selectedModelName == nil {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("home.no_model")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }
            }
            .padding(24)
        }
        .navigationTitle("home.nav_title")
    }
}

struct StatTile: View {
    let title: LocalizedStringKey
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
