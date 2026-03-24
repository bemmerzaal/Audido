import SwiftUI
import AVFoundation

struct RecordingQuickLookPanel: View {
    @Bindable var recording: Recording
    let allTags: [String]
    var onOpenFull: () -> Void
    var onClose: () -> Void

    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0
    @State private var playbackTimer: Timer?
    @State private var summaryExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header with close button
            HStack {
                Text(recording.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Verberg detail panel")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // MARK: - Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Player
                    playerSection
                        .padding()

                    Divider()

                    // Metadata
                    metadataSection
                        .padding()

                    Divider()

                    // Tags
                    tagsSection
                        .padding()

                    // AI Summary (if present)
                    if recording.summaryText != nil {
                        Divider()
                        summarySection
                            .padding()
                    }

                    Divider()

                    // Open full view button — always visible at bottom
                    Button(action: onOpenFull) {
                        Label("Open Full View", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding()
                }
            }
        }
        .onDisappear { stopPlayback() }
        .onChange(of: recording.id) {
            stopPlayback()
            audioPlayer = nil
            playbackProgress = 0
        }
    }

    // MARK: - Player Section

    private var playerSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $playbackProgress, in: 0...1) { editing in
                        if !editing, let player = audioPlayer {
                            player.currentTime = player.duration * playbackProgress
                        }
                    }

                    HStack {
                        Text(formatCurrentTime())
                            .monospacedDigit()
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatDuration(audioPlayer?.duration ?? recording.duration))
                            .monospacedDigit()
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Titel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Titel", text: $recording.title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Notities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $recording.notes)
                    .font(.body)
                    .frame(minHeight: 60, maxHeight: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        if recording.notes.isEmpty {
                            Text("Voeg een korte beschrijving toe...")
                                .foregroundStyle(.tertiary)
                                .font(.body)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags")
                .font(.caption)
                .foregroundStyle(.secondary)

            TagInputView(tags: $recording.tags, suggestions: allTags)
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsible header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    summaryExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(summaryExpanded ? 90 : 0))
                        .frame(width: 12)
                    Image(systemName: "apple.intelligence")
                        .foregroundStyle(.purple)
                    Text("AI Samenvatting")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content with max height + internal scroll
            if summaryExpanded, let summary = recording.summaryText {
                ScrollView {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
                .frame(maxHeight: 200)
            }
        }
    }

    // MARK: - Playback helpers

    private func togglePlayback() {
        isPlaying ? stopPlayback() : startPlayback()
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
            print("Playback error: \(error)")
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func formatCurrentTime() -> String {
        guard let player = audioPlayer else { return "0:00" }
        return formatDuration(player.currentTime)
    }
}
