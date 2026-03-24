import SwiftUI
import SwiftData
import ScreenCaptureKit

struct MeetingCaptureSetupView: View {
    @Environment(MeetingCaptureService.self) private var captureService
    @Environment(AudioDeviceManager.self) private var audioDeviceManager
    @Environment(\.modelContext) private var modelContext
    @State private var isStarting = false
    var onCaptureSaved: (Recording) -> Void

    var body: some View {
        @Bindable var capture = captureService

        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)

                    Text("Meeting Capture")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Record system audio from a meeting app and your microphone")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                // Audio source selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Audio Source")
                        .font(.headline)

                    Picker("Source", selection: $capture.captureAllSystemAudio) {
                        Text("All system audio").tag(true)
                        Text("Specific app").tag(false)
                    }
                    .pickerStyle(.radioGroup)

                    if !captureService.captureAllSystemAudio {
                        if captureService.availableApps.isEmpty {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Loading apps...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Picker("Application", selection: $capture.selectedApp) {
                                Text("Select an app...").tag(nil as SCRunningApplication?)
                                ForEach(captureService.availableApps, id: \.bundleIdentifier) { app in
                                    Text(app.applicationName).tag(app as SCRunningApplication?)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 12))

                // Microphone toggle
                VStack(alignment: .leading, spacing: 12) {
                    Text("Microphone")
                        .font(.headline)

                    Toggle("Include microphone (your voice)", isOn: $capture.includeMicrophone)
                        .toggleStyle(.switch)

                    if captureService.includeMicrophone {
                        Text("Your voice will be mixed with the meeting audio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 12))

                // Error message
                if let error = captureService.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }

                // Start button
                Button {
                    Task { await startCapture() }
                } label: {
                    if isStarting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Start Meeting Capture", systemImage: "record.circle")
                            .font(.title3)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
                .disabled(isStarting || (!captureService.captureAllSystemAudio && captureService.selectedApp == nil))
            }
            .padding(24)
        }
        .frame(maxWidth: 500)
        .navigationTitle("Meeting Capture")
        .task {
            await captureService.fetchAvailableApps()
        }
    }

    private func startCapture() async {
        isStarting = true
        defer { isStarting = false }

        do {
            try await captureService.startCapture(inputDeviceID: audioDeviceManager.resolvedDeviceID)
        } catch {
            captureService.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Active Meeting Capture View

struct ActiveMeetingCaptureView: View {
    @Environment(MeetingCaptureService.self) private var captureService
    @Environment(\.modelContext) private var modelContext
    var onCaptureSaved: (Recording) -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Capture indicator
            VStack(spacing: 16) {
                Image(systemName: "video.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse, isActive: true)

                Text("Meeting Capture Active")
                    .font(.title2)
                    .fontWeight(.medium)

                Text(formatDuration(captureService.currentDuration))
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Audio levels
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "speaker.wave.2")
                        .frame(width: 24)
                    Text("System")
                        .font(.caption)
                        .frame(width: 50, alignment: .leading)
                    AudioLevelIndicator(level: captureService.systemAudioLevel, barCount: 30)
                        .frame(height: 20)
                }

                if captureService.includeMicrophone {
                    HStack {
                        Image(systemName: "mic")
                            .frame(width: 24)
                        Text("Mic")
                            .font(.caption)
                            .frame(width: 50, alignment: .leading)
                        AudioLevelIndicator(level: captureService.micAudioLevel, barCount: 30)
                            .frame(height: 20)
                    }
                }
            }
            .padding(.horizontal, 48)

            // Stop button
            Button {
                Task { await stopCapture() }
            } label: {
                Label("Stop Meeting Capture", systemImage: "stop.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Meeting Capture")
    }

    private func stopCapture() async {
        guard let result = await captureService.stopCapture() else { return }
        guard let fileName = captureService.currentFileName else { return }

        let recording = Recording(
            title: "Meeting \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))",
            duration: result.duration,
            fileName: fileName
        )
        modelContext.insert(recording)
        captureService.currentFileName = nil
        onCaptureSaved(recording)
    }
}
