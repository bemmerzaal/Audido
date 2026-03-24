import SwiftUI

struct ModelManagementView: View {
    @Environment(ModelManager.self) private var modelManager
    @Environment(TranscriptionService.self) private var transcriptionService
    @Environment(AudioDeviceManager.self) private var audioDeviceManager

    var body: some View {
        Form {
            Section {
                if let selected = modelManager.selectedModelName,
                   let model = modelManager.availableModels.first(where: { $0.name == selected }) {
                    LabeledContent("settings.active_model") {
                        Text(model.displayName)
                            .fontWeight(.medium)
                    }
                } else {
                    LabeledContent("settings.active_model") {
                        Text("settings.none")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("settings.current_model")
            }

            Section {
                Picker("settings.app_language", selection: Bindable(modelManager).uiLanguage) {
                    Text("settings.dutch").tag("nl")
                    Text("settings.english").tag("en")
                }
            } header: {
                Text("settings.language")
            }

            Section {
                Picker("settings.microphone", selection: Bindable(audioDeviceManager).selectedDeviceUID) {
                    Text("settings.system_default").tag(nil as String?)
                    Divider()
                    ForEach(audioDeviceManager.inputDevices) { device in
                        Text(device.name).tag(device.uniqueID as String?)
                    }
                }
            } header: {
                Text("settings.audio_input")
            } footer: {
                Text("settings.microphone_hint")
            }

            Section {
                Picker("settings.transcription_language", selection: Bindable(modelManager).selectedLanguage) {
                    ForEach(ModelManager.supportedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }

                Toggle("settings.conversation_mode", isOn: Bindable(modelManager).conversationMode)
            } header: {
                Text("settings.transcription")
            } footer: {
                Text("settings.conversation_hint")
            }

            Section {
                ForEach(modelManager.availableModels) { model in
                    ModelRow(
                        model: model,
                        isSelected: model.name == modelManager.selectedModelName,
                        isDownloading: modelManager.downloadingModelName == model.name,
                        downloadProgress: modelManager.downloadProgress,
                        onDownload: { downloadModel(model.name) },
                        onDelete: { modelManager.deleteModel(model.name) },
                        onSelect: { selectModel(model.name) }
                    )
                }
            } header: {
                Text("settings.available_models")
            } footer: {
                Text("settings.models_hint")
            }

            if let error = modelManager.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 450, minHeight: 400)
        .onAppear {
            modelManager.refreshModels()
            audioDeviceManager.refreshDevices()
        }
    }

    private func downloadModel(_ name: String) {
        Task {
            try? await modelManager.downloadModel(name)
        }
    }

    private func selectModel(_ name: String) {
        modelManager.selectModel(name)
        Task {
            if let folder = modelManager.selectedModelFolder {
                transcriptionService.unloadModel()
                try? await transcriptionService.loadModel(from: folder)
            }
        }
    }
}

struct ModelRow: View {
    let model: WhisperModel
    let isSelected: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .fontWeight(.medium)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .font(.caption)
                    }
                }
                Text(model.sizeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isDownloading {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 120)
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if model.isDownloaded {
                HStack(spacing: 8) {
                    if !isSelected {
                        Button("settings.select") {
                            onSelect()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .controlSize(.small)
                }
            } else {
                Button {
                    onDownload()
                } label: {
                    Label("settings.download", systemImage: "arrow.down.circle")
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
