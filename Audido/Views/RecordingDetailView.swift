import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import SwiftData

struct RecordingDetailView: View {
    @Bindable var recording: Recording
    @Environment(TranscriptionService.self) private var transcriptionService
    @Environment(TranscriptionQueue.self) private var transcriptionQueue
    @Environment(ModelManager.self) private var modelManager
    @Environment(SummaryService.self) private var summaryService
    @Query private var allRecordings: [Recording]
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0
    @State private var playbackTimer: Timer?
    @State private var errorMessage: String?
    @State private var speakerMode: SpeakerMode = .single
    @State private var showInspector = true
    @State private var fontSize: Double = 14
    @State private var copied = false
    @State private var isSummarizing = false
    @State private var isExtractingActions = false
    @State private var showUnavailableAlert = false

    private var allTags: [String] {
        Array(Set(allRecordings.flatMap { $0.tags })).sorted()
    }

    enum SpeakerMode: String, CaseIterable {
        case single = "Single Speaker"
        case multi = "Multi Speaker"
    }

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Main content (left side)
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

                        if transcriptionService.isLoadingModel {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("transcription.model_loading")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        } else if transcriptionService.isModelLoaded {
                            // Speaker mode picker + Transcribe button
                            HStack(spacing: 12) {
                                Picker("transcription.mode", selection: $speakerMode) {
                                    Text("transcription.single_speaker").tag(SpeakerMode.single)
                                    Text("transcription.multi_speaker").tag(SpeakerMode.multi)
                                }
                                .pickerStyle(.menu)
                                .frame(width: 180)

                                Button("transcription.transcribe") {
                                    transcribe()
                                }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.capsule)
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
                } else {
                    TranscriptionTextView(
                        text: recording.transcriptionText,
                        fontSize: $fontSize,
                        summaryText: $recording.summaryText,
                        actionItemsText: $recording.actionItemsText,
                        isSummarizing: $isSummarizing,
                        isExtractingActions: $isExtractingActions
                    )
                }
            }

            // MARK: - Inspector panel (right side, full height)
            if showInspector {
                Divider()

                inspectorPanel
                    .frame(width: 300)
            }
        }
        .navigationTitle($recording.title)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation { showInspector.toggle() }
                } label: {
                    Label("transcription.inspector", systemImage: "sidebar.trailing")
                }
            }
        }
        .alert("error.title", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("error.ok") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(Text("transcription.ai_unavailable"), isPresented: $showUnavailableAlert) {
            Button("error.ok") {}
        } message: {
            Text(summaryService.unavailableReason ?? "Apple Intelligence is not available on this device.")
        }
        .task {
            guard !transcriptionService.isModelLoaded,
                  !transcriptionService.isLoadingModel,
                  let folder = modelManager.selectedModelFolder else { return }
            try? await transcriptionService.loadModel(from: folder)
        }
        .onChange(of: recording.id) {
            stopPlayback()
            audioPlayer = nil
            playbackProgress = 0
            isSummarizing = false
            isExtractingActions = false
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
            errorMessage = String(format: String(localized: "error.playback_failed"), error.localizedDescription)
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

    // MARK: - Inspector Panel

    private var inspectorPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("transcription.options")
                    .font(.headline)
                Spacer()
            }

            // MARK: Details section
            VStack(alignment: .leading, spacing: 10) {
                Text("recording.details")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text("recording.title_label")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    TextField("recording.title_placeholder", text: $recording.title)
                        .textFieldStyle(.roundedBorder)
                }

                // Notes
                VStack(alignment: .leading, spacing: 4) {
                    Text("recording.notes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    TextEditor(text: $recording.notes)
                        .font(.body)
                        .frame(minHeight: 64, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                        .overlay(alignment: .topLeading) {
                            if recording.notes.isEmpty {
                                Text("recording.notes_placeholder")
                                    .font(.body)
                                    .foregroundStyle(Color(nsColor: .placeholderTextColor))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 10)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                // Tags
                VStack(alignment: .leading, spacing: 4) {
                    Text("recording.tags")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    TagInputView(
                        tags: Binding(
                            get: { recording.tags },
                            set: { recording.tags = $0 }
                        ),
                        suggestions: allTags
                    )
                }
            }

            Divider()

            // AI features (only when transcription exists)
            if !recording.transcriptionText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("transcription.ai_summary")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        if summaryService.isAvailable {
                            Task {
                                isSummarizing = true
                                recording.summaryText = nil
                                await summaryService.summarize(
                                    text: recording.transcriptionText,
                                    language: modelManager.selectedLanguage
                                )
                                recording.summaryText = summaryService.summaryText
                                isSummarizing = false
                            }
                        } else {
                            showUnavailableAlert = true
                        }
                    } label: {
                        Label(recording.summaryText != nil ? "transcription.regenerate_summary" : "transcription.ai_summary",
                              systemImage: "apple.intelligence")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                    .tint(.purple)
                    .disabled(isSummarizing)

                    Button {
                        if summaryService.isAvailable {
                            Task {
                                isExtractingActions = true
                                recording.actionItemsText = nil
                                await summaryService.extractActionItems(
                                    text: recording.transcriptionText,
                                    language: modelManager.selectedLanguage
                                )
                                recording.actionItemsText = summaryService.actionItemsText
                                isExtractingActions = false
                            }
                        } else {
                            showUnavailableAlert = true
                        }
                    } label: {
                        Label(recording.actionItemsText != nil ? "transcription.regenerate_actions" : "transcription.action_items",
                              systemImage: "checklist")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                    .tint(.orange)
                    .disabled(isExtractingActions)
                }

                Divider()
            }

            // Font size
            VStack(alignment: .leading, spacing: 8) {
                Text("transcription.font_size")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Image(systemName: "textformat.size.smaller")
                        .foregroundStyle(.secondary)
                    Slider(value: $fontSize, in: 10...28, step: 1)
                    Image(systemName: "textformat.size.larger")
                        .foregroundStyle(.secondary)
                }

                Text("\(Int(fontSize)) pt")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // Copy & Export (only when transcription exists)
            if !recording.transcriptionText.isEmpty {
                Divider()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(recording.transcriptionText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    Label {
                        if copied {
                            Text("transcription.copied")
                        } else {
                            Text("transcription.copy_text")
                        }
                    } icon: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .buttonBorderShape(.capsule)

                Button {
                    exportToFile()
                } label: {
                    Label("transcription.export_txt", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .buttonBorderShape(.capsule)

                Divider()

                // Word count info
                VStack(alignment: .leading, spacing: 4) {
                    Text("transcription.statistics")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    let words = recording.transcriptionText.split(separator: " ").count
                    let chars = recording.transcriptionText.count

                    HStack {
                        Text("transcription.words")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(words)")
                            .monospacedDigit()
                    }
                    .font(.caption)

                    HStack {
                        Text("transcription.characters")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(chars)")
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            }

            Spacer()
        }
        .padding()
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "transcription.txt"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            var exportText = ""
            if let summary = recording.summaryText {
                exportText += "=== AI SUMMARY ===\n\(summary)\n\n"
            }
            if let actions = recording.actionItemsText {
                exportText += "=== ACTION ITEMS ===\n\(actions)\n\n"
            }
            if recording.summaryText != nil || recording.actionItemsText != nil {
                exportText += "=== TRANSCRIPTION ===\n"
            }
            exportText += recording.transcriptionText
            try? exportText.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
