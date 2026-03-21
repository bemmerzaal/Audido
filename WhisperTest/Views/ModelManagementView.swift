import SwiftUI

struct ModelManagementView: View {
    @Environment(ModelManager.self) private var modelManager
    @Environment(TranscriptionService.self) private var transcriptionService

    var body: some View {
        Form {
            Section {
                if let selected = modelManager.selectedModelName,
                   let model = modelManager.availableModels.first(where: { $0.name == selected }) {
                    LabeledContent("Active Model") {
                        Text(model.displayName)
                            .fontWeight(.medium)
                    }
                } else {
                    LabeledContent("Active Model") {
                        Text("None")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Current Model")
            }

            Section {
                Picker("Transcription Language", selection: Bindable(modelManager).selectedLanguage) {
                    ForEach(ModelManager.supportedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
            } header: {
                Text("Language")
            } footer: {
                Text("Select the language of the audio you want to transcribe. Use Auto-detect if unsure.")
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
                Text("Available Models")
            } footer: {
                Text("Multilingual models support Dutch, English, and 90+ other languages. Larger models are more accurate but use more memory and are slower.")
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
                        Button("Select") {
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
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
