import Foundation
import SwiftData

enum SourceType: String, Codable {
    case recording = "recording"
    case importedFile = "import"
    case podcast = "podcast"
}

@Model
final class Recording {
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var fileName: String
    var transcriptionText: String
    var isTranscribing: Bool
    var sourceTypeRaw: String
    // Podcast metadata
    var podcastName: String?
    var podcastArtworkURLString: String?
    var episodeDuration: String?

    init(
        title: String,
        createdAt: Date = .now,
        duration: TimeInterval = 0,
        fileName: String,
        transcriptionText: String = "",
        isTranscribing: Bool = false,
        sourceType: SourceType = .recording,
        podcastName: String? = nil,
        podcastArtworkURLString: String? = nil,
        episodeDuration: String? = nil
    ) {
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.fileName = fileName
        self.transcriptionText = transcriptionText
        self.isTranscribing = isTranscribing
        self.sourceTypeRaw = sourceType.rawValue
        self.podcastName = podcastName
        self.podcastArtworkURLString = podcastArtworkURLString
        self.episodeDuration = episodeDuration
    }

    var sourceType: SourceType {
        get { SourceType(rawValue: sourceTypeRaw) ?? .recording }
        set { sourceTypeRaw = newValue.rawValue }
    }

    var podcastArtworkURL: URL? {
        podcastArtworkURLString.flatMap { URL(string: $0) }
    }

    var fileURL: URL {
        // For podcasts and imports, fileName is the full path
        if sourceType == .podcast || sourceType == .importedFile {
            return URL(fileURLWithPath: fileName)
        }
        return Self.recordingsDirectory.appendingPathComponent(fileName)
    }

    var sourceIcon: String {
        switch sourceType {
        case .recording: return "waveform"
        case .importedFile: return "doc.fill"
        case .podcast: return "mic.fill"
        }
    }

    var sourceLabel: String {
        switch sourceType {
        case .recording: return "Recording"
        case .importedFile: return "Import"
        case .podcast: return "Podcast"
        }
    }

    static var recordingsDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
