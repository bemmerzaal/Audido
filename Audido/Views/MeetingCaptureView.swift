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

                    Text("meeting.title")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("meeting.subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                // Audio source selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("meeting.audio_source")
                        .font(.headline)

                    Picker("meeting.source", selection: $capture.captureAllSystemAudio) {
                        Text("meeting.all_system_audio").tag(true)
                        Text("meeting.specific_app").tag(false)
                    }
                    .pickerStyle(.radioGroup)

                    if !captureService.captureAllSystemAudio {
                        if captureService.availableApps.isEmpty {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("meeting.loading_apps")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Picker("meeting.application", selection: $capture.selectedApp) {
                                Text("meeting.select_app").tag(nil as SCRunningApplication?)
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
                    Text("meeting.microphone")
                        .font(.headline)

                    Toggle("meeting.include_microphone", isOn: $capture.includeMicrophone)
                        .toggleStyle(.switch)

                    if captureService.includeMicrophone {
                        Text("meeting.mic_hint")
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
                        Label("meeting.start_capture", systemImage: "record.circle")
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
        .navigationTitle(Text("meeting.title"))
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
        VStack(spacing: 28) {
            Spacer()

            WaveformPill(
                level: max(captureService.systemAudioLevel, captureService.micAudioLevel),
                duration: captureService.currentDuration
            )

            Button {
                Task { await stopCapture() }
            } label: {
                Label("meeting.stop_capture", systemImage: "stop.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(Text("meeting.title"))
    }

    private func stopCapture() async {
        guard let result = await captureService.stopCapture() else { return }
        guard let fileName = captureService.currentFileName else { return }

        let recording = Recording(
            title: "\(String(localized: "meeting.title_prefix")) \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))",
            duration: result.duration,
            fileName: fileName
        )
        modelContext.insert(recording)
        captureService.currentFileName = nil
        onCaptureSaved(recording)
    }
}
