import SwiftUI

struct ModelManagementView: View {
    @Environment(ModelManager.self) private var modelManager
    @Environment(TranscriptionService.self) private var transcriptionService
    @Environment(AudioDeviceManager.self) private var audioDeviceManager

    var body: some View {
        let lang = modelManager.uiLanguage
        Form {
            Section {
                if let selected = modelManager.selectedModelName,
                   let model = modelManager.availableModels.first(where: { $0.name == selected }) {
                    LabeledContent {
                        Text(model.displayName)
                            .fontWeight(.medium)
                    } label: {
                        Text(AppLocalization.string("settings.active_model", uiLanguage: lang))
                    }
                } else {
                    LabeledContent {
                        Text(AppLocalization.string("settings.none", uiLanguage: lang))
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(AppLocalization.string("settings.active_model", uiLanguage: lang))
                    }
                }
            } header: {
                Text(AppLocalization.string("settings.current_model", uiLanguage: lang))
            }

            Section {
                Picker(selection: Bindable(modelManager).uiLanguage) {
                    Text(AppLocalization.string("settings.dutch", uiLanguage: lang)).tag("nl")
                    Text(AppLocalization.string("settings.english", uiLanguage: lang)).tag("en")
                } label: {
                    Text(AppLocalization.string("settings.app_language", uiLanguage: lang))
                }
            } header: {
                Text(AppLocalization.string("settings.language", uiLanguage: lang))
            }

            Section {
                Picker(selection: Bindable(audioDeviceManager).selectedDeviceUID) {
                    Text(AppLocalization.string("settings.system_default", uiLanguage: lang)).tag(nil as String?)
                    Divider()
                    ForEach(audioDeviceManager.inputDevices) { device in
                        Text(device.name).tag(device.uniqueID as String?)
                    }
                } label: {
                    Text(AppLocalization.string("settings.microphone", uiLanguage: lang))
                }
            } header: {
                Text(AppLocalization.string("settings.audio_input", uiLanguage: lang))
            } footer: {
                Text(AppLocalization.string("settings.microphone_hint", uiLanguage: lang))
            }

            Section {
                Picker(selection: Bindable(modelManager).selectedLanguage) {
                    ForEach(ModelManager.supportedLanguages, id: \.code) { codeName in
                        Text(ModelManager.localizedLanguageName(code: codeName.code, fallback: codeName.name, uiLanguage: lang))
                            .tag(codeName.code)
                    }
                } label: {
                    Text(AppLocalization.string("settings.transcription_language", uiLanguage: lang))
                }

                Toggle(isOn: Bindable(modelManager).conversationMode) {
                    Text(AppLocalization.string("settings.conversation_mode", uiLanguage: lang))
                }
            } header: {
                Text(AppLocalization.string("settings.transcription", uiLanguage: lang))
            } footer: {
                Text(AppLocalization.string("settings.conversation_hint", uiLanguage: lang))
            }

            Section {
                ForEach(modelManager.availableModels) { model in
                    ModelRow(
                        model: model,
                        uiLanguage: lang,
                        isSelected: model.name == modelManager.selectedModelName,
                        isDownloading: modelManager.downloadingModelName == model.name,
                        downloadProgress: modelManager.downloadProgress,
                        onDownload: { downloadModel(model.name) },
                        onDelete: { modelManager.deleteModel(model.name) },
                        onSelect: { selectModel(model.name) }
                    )
                }
            } header: {
                Text(AppLocalization.string("settings.available_models", uiLanguage: lang))
            } footer: {
                Text(AppLocalization.string("settings.models_hint", uiLanguage: lang))
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
        .id(lang)
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
    let uiLanguage: String
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
                        Button(AppLocalization.string("settings.select", uiLanguage: uiLanguage)) {
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
                    Label {
                        Text(AppLocalization.string("settings.download", uiLanguage: uiLanguage))
                    } icon: {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
