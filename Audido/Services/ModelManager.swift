import WhisperKit
import Observation
import Foundation

struct WhisperModel: Identifiable {
    var id: String { name }
    let name: String
    let displayName: String
    let sizeDescription: String
    var isDownloaded: Bool
    var downloadProgress: Double
}

@Observable
final class ModelManager {
    var availableModels: [WhisperModel] = []
    var selectedModelName: String? {
        didSet {
            UserDefaults.standard.set(selectedModelName, forKey: "selectedModelName")
        }
    }
    var selectedLanguage: String {
        didSet {
            UserDefaults.standard.set(selectedLanguage, forKey: "selectedLanguage")
        }
    }
    var conversationMode: Bool {
        didSet {
            UserDefaults.standard.set(conversationMode, forKey: "conversationMode")
        }
    }
    var uiLanguage: String {
        didSet {
            UserDefaults.standard.set(uiLanguage, forKey: "uiLanguage")
        }
    }
    var isDownloading = false
    var downloadingModelName: String?
    var downloadProgress: Double = 0
    var errorMessage: String?

    static let supportedLanguages: [(code: String, name: String)] = [
        ("nl", "Nederlands"),
        ("en", "English"),
        ("de", "Deutsch"),
        ("fr", "Français"),
        ("es", "Español"),
        ("it", "Italiano"),
        ("pt", "Português"),
        ("ja", "日本語"),
        ("zh", "中文"),
        ("ko", "한국어"),
        ("auto", "Auto-detect"),
    ]

    private static let modelDefinitions: [(name: String, display: String, size: String)] = [
        ("openai_whisper-tiny", "Tiny", "~75 MB"),
        ("openai_whisper-base", "Base", "~150 MB"),
        ("openai_whisper-small", "Small", "~500 MB"),
        ("openai_whisper-medium", "Medium", "~800 MB"),
        ("openai_whisper-large-v3", "Large v3", "~1.5 GB"),
    ]

    init() {
        selectedModelName = UserDefaults.standard.string(forKey: "selectedModelName")
        selectedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "nl"
        conversationMode = UserDefaults.standard.bool(forKey: "conversationMode")
        uiLanguage = UserDefaults.standard.string(forKey: "uiLanguage") ?? "nl"
        refreshModels()
    }

    var selectedModelFolder: String? {
        guard let name = selectedModelName else { return nil }
        let folder = Self.modelsDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: folder.path) {
            return folder.path
        }
        return nil
    }

    /// Base directory passed to WhisperKit.download(downloadBase:)
    static var modelsBaseDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Actual directory where models end up (nested by HuggingFace Hub)
    static var modelsDirectory: URL {
        modelsBaseDirectory
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
    }

    func refreshModels() {
        availableModels = Self.modelDefinitions.map { def in
            let folder = Self.modelsDirectory.appendingPathComponent(def.name)
            let downloaded = FileManager.default.fileExists(atPath: folder.path)
            return WhisperModel(
                name: def.name,
                displayName: def.display,
                sizeDescription: def.size,
                isDownloaded: downloaded,
                downloadProgress: downloaded ? 1.0 : 0.0
            )
        }
    }

    func downloadModel(_ name: String) async throws {
        isDownloading = true
        downloadingModelName = name
        downloadProgress = 0
        errorMessage = nil

        do {
            let folder = try await WhisperKit.download(
                variant: name,
                downloadBase: Self.modelsBaseDirectory
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress.fractionCompleted
                }
            }
            print("Model downloaded to: \(folder)")
            refreshModels()
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
            isDownloading = false
            downloadingModelName = nil
            throw error
        }

        isDownloading = false
        downloadingModelName = nil
        downloadProgress = 0
    }

    func deleteModel(_ name: String) {
        let folder = Self.modelsDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: folder)
        if selectedModelName == name {
            selectedModelName = nil
        }
        refreshModels()
    }

    func selectModel(_ name: String) {
        selectedModelName = name
    }
}
