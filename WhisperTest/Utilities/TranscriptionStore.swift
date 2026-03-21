import Foundation

/// Persists transcription text to disk for podcast episodes and imported files
enum TranscriptionStore {
    private static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Transcriptions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save(text: String, for key: String) {
        let fileURL = directory.appendingPathComponent("\(key).txt")
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func load(for key: String) -> String? {
        let fileURL = directory.appendingPathComponent("\(key).txt")
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    static func delete(for key: String) {
        let fileURL = directory.appendingPathComponent("\(key).txt")
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Generate a stable key for a podcast episode
    static func key(for episode: PodcastEpisode) -> String {
        "podcast-\(episode.id.hashValue)"
    }

    /// Generate a stable key for an imported file
    static func key(for fileURL: URL) -> String {
        "import-\(fileURL.lastPathComponent.hashValue)"
    }
}
