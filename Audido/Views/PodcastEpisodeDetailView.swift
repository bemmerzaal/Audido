import SwiftUI
import SwiftData
import AVFoundation

struct PodcastEpisodeDetailView: View {
    @Environment(PodcastService.self) private var podcastService
    @Environment(TranscriptionService.self) private var transcriptionService
    @Environment(TranscriptionQueue.self) private var transcriptionQueue
    @Environment(ModelManager.self) private var modelManager
    @Environment(\.modelContext) private var modelContext
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
    @State private var existingRecording: Recording?
    @State private var fontSize: Double = 14
    @State private var summaryText: String?
    @State private var actionItemsText: String?
    @State private var isSummarizing = false
    @State private var isExtractingActions = false

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
                downloadProgressView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isTranscribing {
                TranscriptionProgressView(task: existingRecording.flatMap { transcriptionQueue.task(for: $0) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !transcriptionText.isEmpty {
                TranscriptionTextView(
                    text: transcriptionText,
                    fontSize: $fontSize,
                    summaryText: $summaryText,
                    actionItemsText: $actionItemsText,
                    isSummarizing: $isSummarizing,
                    isExtractingActions: $isExtractingActions
                )
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "text.below.photo")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    if transcriptionService.isModelLoaded {
                        HStack(spacing: 12) {
                            Picker("transcription.mode", selection: $speakerMode) {
                                Text("transcription.single_speaker").tag(SpeakerMode.single)
                                Text("transcription.multi_speaker").tag(SpeakerMode.multi)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 180)

                            Button("podcast.download_transcribe") {
                                Task { await downloadAndTranscribe() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        Text("transcription.no_model")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(episode.title)
        .alert("error.title", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("error.ok") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            loadExistingRecording()
        }
        .onDisappear {
            stopPlayback()
            audioPlayer = nil
        }
        .onChange(of: existingRecording?.isTranscribing) { _, newValue in
            if let newValue, !newValue, isTranscribing {
                isTranscribing = false
                if let text = existingRecording?.transcriptionText, !text.isEmpty {
                    transcriptionText = text
                }
            }
        }
    }

    // MARK: - Load existing

    private func loadExistingRecording() {
        let episodeId = episode.id
        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.title == episodeId || $0.podcastName != nil }
        )
        if let results = try? modelContext.fetch(descriptor) {
            // Find by matching title to episode title
            if let match = results.first(where: { $0.title == episode.title && $0.sourceType == .podcast }) {
                existingRecording = match
                transcriptionText = match.transcriptionText
                if FileManager.default.fileExists(atPath: match.fileURL.path) {
                    localAudioURL = match.fileURL
                }
            }
        }
    }

    // MARK: - Download Progress with Controls

    private var downloadProgressView: some View {
        VStack(spacing: 16) {
            ProgressView(value: podcastService.downloadProgress)
                .progressViewStyle(.linear)
                .frame(width: 300)

            if podcastService.isPaused {
                Text("podcast.paused")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else if podcastService.downloadProgress >= 0.85 {
                Text("podcast.converting_audio")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                VStack(spacing: 4) {
                    Text("podcast.downloading_percent \(Int(podcastService.downloadProgress / 0.85 * 100))")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    if podcastService.totalBytes > 0 {
                        Text("\(formatFileSize(podcastService.downloadedBytes)) / \(formatFileSize(podcastService.totalBytes))")
                            .foregroundStyle(.tertiary)
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
            }

            if podcastService.downloadProgress < 0.85 {
                HStack(spacing: 12) {
                    if podcastService.isPaused {
                        Button {
                            podcastService.resumeDownload()
                        } label: {
                            Label("podcast.resume", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            podcastService.pauseDownload()
                        } label: {
                            Label("podcast.pause", systemImage: "pause.fill")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(role: .destructive) {
                        podcastService.cancelDownload()
                    } label: {
                        Label("podcast.cancel_download", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }
            }
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
            errorMessage = String(format: String(localized: "error.playback_failed"), error.localizedDescription)
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

            let recording = getOrCreateRecording(audioURL: wavURL)
            isTranscribing = true
            transcriptionQueue.enqueue(
                recording: recording,
                audioURL: wavURL,
                language: modelManager.selectedLanguage,
                conversationMode: speakerMode == .multi
            )
        } catch is CancellationError {
            // User cancelled download
        } catch {
            isTranscribing = false
            errorMessage = String(format: String(localized: "import.failed"), error.localizedDescription)
        }
    }

    private func getOrCreateRecording(audioURL: URL) -> Recording {
        if let existing = existingRecording {
            existing.fileName = audioURL.path
            return existing
        }
        let recording = Recording(
            title: episode.title,
            duration: audioPlayer?.duration ?? 0,
            fileName: audioURL.path,
            sourceType: .podcast,
            podcastName: podcast.name,
            podcastArtworkURLString: podcast.artworkURL?.absoluteString,
            episodeDuration: episode.duration
        )
        modelContext.insert(recording)
        existingRecording = recording
        return recording
    }
}
