import Foundation
import SwiftUI
import Observation

enum TranscriptionTaskState: Equatable {
    case queued
    case active
    case completed
    case failed(String)
    case cancelled
}

@Observable
final class TranscriptionTask: Identifiable {
    let id = UUID()
    let recording: Recording
    let audioURL: URL
    let language: String
    let conversationMode: Bool

    var progress: Double = 0
    var statusMessage: String = String(localized: "progress.in_queue")
    var state: TranscriptionTaskState = .queued
    var isCancelled = false

    init(recording: Recording, audioURL: URL? = nil, language: String, conversationMode: Bool) {
        self.recording = recording
        self.audioURL = audioURL ?? recording.fileURL
        self.language = language
        self.conversationMode = conversationMode
    }
}
