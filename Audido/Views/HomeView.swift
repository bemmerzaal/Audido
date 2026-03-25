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

    private var recentRecordings: [Recording] {
        Array(recordings.sorted { $0.createdAt > $1.createdAt }.prefix(3))
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
                        icon: "text.word.spacing",
                        color: Color.accentColor
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

                // Recents
                if !recordings.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("home.recents")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        ForEach(recentRecordings) { recording in
                            Button { onSelectRecording(recording) } label: {
                                RecentRecordingTile(recording: recording)
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("home.nav_title")
    }
}

struct RecentRecordingTile: View {
    let recording: Recording

    private var iconColor: Color {
        switch recording.sourceType {
        case .recording: .red
        case .importedFile: .blue
        case .podcast: .purple
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: recording.sourceIcon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(recording.createdAt, style: .date)
                    Text("·")
                    if recording.sourceType == .recording {
                        Text(formatDuration(recording.duration))
                    } else {
                        Text(recording.sourceLabel)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if recording.isTranscribing {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.7)
                    Text("home.transcribing")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else if !recording.transcriptionText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("home.transcribed")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "doc.circle")
                        .foregroundStyle(.secondary)
                    Text("home.not_transcribed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
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
