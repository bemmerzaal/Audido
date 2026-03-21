import Foundation
import SwiftData

@Model
final class Recording {
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var fileName: String
    var transcriptionText: String
    var isTranscribing: Bool

    init(title: String, createdAt: Date = .now, duration: TimeInterval = 0, fileName: String, transcriptionText: String = "", isTranscribing: Bool = false) {
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.fileName = fileName
        self.transcriptionText = transcriptionText
        self.isTranscribing = isTranscribing
    }

    var fileURL: URL {
        Self.recordingsDirectory.appendingPathComponent(fileName)
    }

    static var recordingsDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
