import SwiftUI
import SwiftData
import AVFoundation

struct ImportedFileView: View {
    @Environment(PodcastService.self) private var podcastService
    @Environment(TranscriptionService.self) private var transcriptionService
    @Environment(TranscriptionQueue.self) private var transcriptionQueue
    @Environment(ModelManager.self) private var modelManager
    @Environment(\.modelContext) private var modelContext
    let fileURL: URL

    @State private var transcriptionText = ""
    @State private var isTranscribing = false
    @State private var isConverting = false
    @State private var speakerMode: SpeakerMode = .single
    @State private var errorMessage: String?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0
    @State private var playbackTimer: Timer?
    @State private var wavURL: URL?
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
            // File info header
            fileHeader
                .padding()

            Divider()

            // Playback bar
            playbackBar
                .padding()
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top)

            Divider()
                .padding(.top)

            // Content area
            if isConverting {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("import.converting")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
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
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    if transcriptionService.isLoadingModel {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("transcription.model_loading")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    } else if transcriptionService.isModelLoaded {
                        HStack(spacing: 12) {
                            Picker("transcription.mode", selection: $speakerMode) {
                                Text("transcription.single_speaker").tag(SpeakerMode.single)
                                Text("transcription.multi_speaker").tag(SpeakerMode.multi)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 180)

                            Button {
                                Task { await transcribe() }
                            } label: {
                                Text("transcription.transcribe")
                                    .audidoToolbarFilledCapsule(background: Color.accentColor)
                            }
                            .buttonStyle(.plain)
                        }

                        Text(speakerMode == .multi
                             ? "transcription.multi_hint"
                             : "transcription.single_hint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("transcription.no_model")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(fileURL.deletingPathExtension().lastPathComponent)
        .alert("error.title", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("error.ok") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            setupPlayer()
            loadExistingRecording()
        }
        .task {
            // Start model loading as soon as this view appears, in case ContentView's
            // startup task hasn't finished yet (race condition on fresh install).
            guard !transcriptionService.isModelLoaded,
                  !transcriptionService.isLoadingModel,
                  let folder = modelManager.selectedModelFolder else { return }
            try? await transcriptionService.loadModel(from: folder)
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
        let path = fileURL.path
        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.fileName == path }
        )
        if let match = try? modelContext.fetch(descriptor).first {
            existingRecording = match
            transcriptionText = match.transcriptionText
        }
    }

    // MARK: - File Header

    private var fileHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(fileURL.lastPathComponent)
                    .fontWeight(.medium)
                    .lineLimit(1)

                let ext = fileURL.pathExtension.uppercased()
                Text(String(format: String(localized: "import.imported_file"), ext))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let size = attrs[.size] as? Int64 {
                    Text(formatFileSize(size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    private func setupPlayer() {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.prepareToPlay()
        } catch {
            // Player creation failed
        }
    }

    private func togglePlayback() {
        if isPlaying { stopPlayback() } else { startPlayback() }
    }

    private func startPlayback() {
        do {
            if audioPlayer == nil {
                audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
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

    // MARK: - Transcribe

    private func transcribe() async {
        do {
            // Convert to WAV if not already
            let audioURL: URL
            if fileURL.pathExtension.lowercased() == "wav" {
                audioURL = fileURL
            } else {
                isConverting = true
                audioURL = try await podcastService.convertImportedFile(at: fileURL)
                wavURL = audioURL
                isConverting = false
            }

            let recording = getOrCreateRecording()
            isTranscribing = true
            transcriptionQueue.enqueue(
                recording: recording,
                audioURL: audioURL,
                language: modelManager.selectedLanguage,
                conversationMode: speakerMode == .multi
            )
        } catch {
            isConverting = false
            isTranscribing = false
            errorMessage = String(format: String(localized: "import.failed"), error.localizedDescription)
        }
    }

    private func getOrCreateRecording() -> Recording {
        if let existing = existingRecording {
            return existing
        }
        let recording = Recording(
            title: fileURL.deletingPathExtension().lastPathComponent,
            duration: audioPlayer?.duration ?? 0,
            fileName: fileURL.path,
            sourceType: .importedFile
        )
        modelContext.insert(recording)
        existingRecording = recording
        return recording
    }
}
