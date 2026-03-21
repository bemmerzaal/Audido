import SwiftUI
import AVFoundation

struct ImportedFileView: View {
    @Environment(PodcastService.self) private var podcastService
    @Environment(TranscriptionService.self) private var transcriptionService
    @Environment(ModelManager.self) private var modelManager
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
                    Text("Converting audio to WAV...")
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
                    Image(systemName: "doc.text.magnifyingglass")
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

                            Button("Transcribe") {
                                Task { await transcribe() }
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
            }
        }
        .navigationTitle(fileURL.deletingPathExtension().lastPathComponent)
        .alert("Error", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            stopPlayback()
            audioPlayer = nil
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
                Text("Imported \(ext) file")
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
            // File might need conversion to play
            print("Could not create player for imported file: \(error)")
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
            errorMessage = "Could not play audio: \(error.localizedDescription)"
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

            isTranscribing = true
            let conversationMode = speakerMode == .multi
            let text = try await transcriptionService.transcribe(
                audioURL: audioURL,
                language: modelManager.selectedLanguage,
                conversationMode: conversationMode
            )
            transcriptionText = text
            isTranscribing = false
        } catch {
            isConverting = false
            isTranscribing = false
            errorMessage = "Failed: \(error.localizedDescription)"
        }
    }
}
