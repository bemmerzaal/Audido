import SwiftUI
import AVFoundation

struct PodcastEpisodeDetailView: View {
    @Environment(PodcastService.self) private var podcastService
    @Environment(TranscriptionService.self) private var transcriptionService
    @Environment(ModelManager.self) private var modelManager
    let episode: PodcastEpisode
    let podcast: Podcast

    @State private var transcriptionText = ""
    @State private var isTranscribing = false
    @State private var speakerMode: SpeakerMode = .single
    @State private var errorMessage: String?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0
    @State private var playbackTimer: Timer?
    @State private var localAudioURL: URL?

    enum SpeakerMode: String, CaseIterable {
        case single = "Single Speaker"
        case multi = "Multi Speaker"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Episode info header
            episodeHeader
                .padding()

            Divider()

            // Playback bar (only when audio is downloaded)
            if localAudioURL != nil {
                playbackBar
                    .padding()
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.top)
            }

            Divider()
                .padding(.top)

            // Content area
            if podcastService.isDownloading {
                VStack(spacing: 12) {
                    ProgressView(value: podcastService.downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 250)
                    Text(podcastService.downloadProgress < 0.8
                         ? "Downloading episode... \(Int(podcastService.downloadProgress / 0.8 * 100))%"
                         : "Converting audio...")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isTranscribing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Transcribing...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !transcriptionText.isEmpty {
                ScrollView {
                    Text(transcriptionText)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "text.below.photo")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    if transcriptionService.isModelLoaded {
                        HStack(spacing: 12) {
                            Picker("Mode", selection: $speakerMode) {
                                ForEach(SpeakerMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 180)

                            Button("Download & Transcribe") {
                                Task { await downloadAndTranscribe() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        Text("Download and select a model in Settings to transcribe.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(episode.title)
        .alert("Error", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear {
            stopPlayback()
            audioPlayer = nil
        }
    }

    // MARK: - Episode Header

    private var episodeHeader: some View {
        HStack(spacing: 12) {
            AsyncImage(url: podcast.artworkURL) { image in
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
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(podcast.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(episode.title)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let date = episode.publishedDate {
                        Text(date, style: .date)
                    }
                    if let duration = episode.duration {
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

            Text(formatDuration(audioPlayer?.duration ?? 0))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func togglePlayback() {
        if isPlaying { stopPlayback() } else { startPlayback() }
    }

    private func startPlayback() {
        guard let url = localAudioURL else { return }
        do {
            if audioPlayer == nil {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
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

    // MARK: - Download & Transcribe

    private func downloadAndTranscribe() async {
        do {
            let wavURL = try await podcastService.downloadAndConvert(episode: episode)
            localAudioURL = wavURL

            isTranscribing = true
            let conversationMode = speakerMode == .multi
            let text = try await transcriptionService.transcribe(
                audioURL: wavURL,
                language: modelManager.selectedLanguage,
                conversationMode: conversationMode
            )
            transcriptionText = text
            isTranscribing = false
        } catch {
            isTranscribing = false
            errorMessage = "Failed: \(error.localizedDescription)"
        }
    }
}
