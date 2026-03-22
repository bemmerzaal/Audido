import SwiftUI
import AVFoundation

struct RecordingDetailView: View {
    @Bindable var recording: Recording
    @Environment(TranscriptionService.self) private var transcriptionService
    @Environment(TranscriptionQueue.self) private var transcriptionQueue
    @Environment(ModelManager.self) private var modelManager
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0
    @State private var playbackTimer: Timer?
    @State private var errorMessage: String?
    @State private var speakerMode: SpeakerMode = .single

    enum SpeakerMode: String, CaseIterable {
        case single = "Single Speaker"
        case multi = "Multi Speaker"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header for podcast items
            if recording.sourceType == .podcast {
                podcastHeader
                    .padding()
                Divider()
            }

            // Playback controls
            playbackBar
                .padding()
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                .padding()

            Divider()

            // Transcription area
            if recording.isTranscribing {
                TranscriptionProgressView(task: transcriptionQueue.task(for: recording))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if recording.transcriptionText.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "text.word.spacing")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    if transcriptionService.isModelLoaded {
                        // Speaker mode picker + Transcribe button
                        HStack(spacing: 12) {
                            Picker("Mode", selection: $speakerMode) {
                                ForEach(SpeakerMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 180)

                            Button("Transcribe") {
                                transcribe()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Text(speakerMode == .multi
                             ? "Identifies different speakers in the conversation."
                             : "Transcribes all audio as a single speaker.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Download and select a model in Settings to transcribe.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TranscriptionTextView(text: recording.transcriptionText)
            }
        }
        .navigationTitle($recording.title)
        .alert("Error", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: recording.id) {
            stopPlayback()
            audioPlayer = nil
            playbackProgress = 0
        }
        .onDisappear {
            stopPlayback()
            audioPlayer = nil
        }
    }

    // MARK: - Podcast Header

    private var podcastHeader: some View {
        HStack(spacing: 12) {
            if let artworkURL = recording.podcastArtworkURL {
                AsyncImage(url: artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "mic.fill")
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                if let podcastName = recording.podcastName {
                    Text(podcastName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text(recording.createdAt, style: .date)
                    if let duration = recording.episodeDuration {
                        Text("·")
                        Text(duration)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Playback

    private var playbackBar: some View {
        HStack(spacing: 16) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
            }
            .buttonStyle(.plain)

            Slider(value: $playbackProgress, in: 0...1) { editing in
                if !editing, let player = audioPlayer {
                    player.currentTime = player.duration * playbackProgress
                }
            }

            Text(formatDuration(audioPlayer?.duration ?? recording.duration))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        do {
            if audioPlayer == nil {
                audioPlayer = try AVAudioPlayer(contentsOf: recording.fileURL)
                audioPlayer?.prepareToPlay()
            }
            audioPlayer?.play()
            isPlaying = true

            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                Task { @MainActor in
                    guard let player = audioPlayer else { return }
                    if player.isPlaying {
                        playbackProgress = player.currentTime / player.duration
                    } else {
                        stopPlayback()
                        playbackProgress = 0
                    }
                }
            }
        } catch {
            errorMessage = "Could not play audio: \(error.localizedDescription)"
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func transcribe() {
        transcriptionQueue.enqueue(
            recording: recording,
            language: modelManager.selectedLanguage,
            conversationMode: speakerMode == .multi
        )
    }
}
