import Foundation
import Observation

@Observable
final class TranscriptionQueue {
    private(set) var tasks: [TranscriptionTask] = []
    private var processingTask: Task<Void, Never>?
    private let transcriptionService: TranscriptionService

    var activeTasks: [TranscriptionTask] {
        tasks.filter { $0.state == .queued || $0.state == .active }
    }

    var hasActiveTasks: Bool {
        !activeTasks.isEmpty
    }

    init(transcriptionService: TranscriptionService) {
        self.transcriptionService = transcriptionService
    }

    func enqueue(recording: Recording, audioURL: URL? = nil, language: String, conversationMode: Bool) {
        let task = TranscriptionTask(
            recording: recording,
            audioURL: audioURL,
            language: language,
            conversationMode: conversationMode
        )
        recording.isTranscribing = true
        tasks.append(task)
        startProcessingIfNeeded()
    }

    func cancelTask(_ task: TranscriptionTask) {
        task.isCancelled = true
        if task.state == .queued {
            task.state = .cancelled
            task.recording.isTranscribing = false
            cleanupCompleted()
        }
    }

    func task(for recording: Recording) -> TranscriptionTask? {
        tasks.first(where: { $0.recording.id == recording.id && ($0.state == .queued || $0.state == .active) })
    }

    // MARK: - Processing

    private func startProcessingIfNeeded() {
        guard processingTask == nil else { return }
        processingTask = Task {
            while let next = tasks.first(where: { $0.state == .queued }) {
                await processTask(next)
            }
            processingTask = nil
        }
    }

    private func processTask(_ task: TranscriptionTask) async {
        await MainActor.run {
            task.state = .active
            task.statusMessage = "Transcribing..."
        }

        do {
            let text = try await transcriptionService.transcribe(
                audioURL: task.audioURL,
                language: task.language,
                conversationMode: task.conversationMode,
                onProgress: { progress, message in
                    Task { @MainActor in
                        task.progress = progress
                        task.statusMessage = message
                    }
                },
                cancelCheck: { task.isCancelled }
            )

            await MainActor.run {
                task.recording.transcriptionText = text
                task.recording.isTranscribing = false
                task.state = .completed
                cleanupCompleted()
            }
        } catch TranscriptionError.cancelled {
            await MainActor.run {
                task.state = .cancelled
                task.recording.isTranscribing = false
                cleanupCompleted()
            }
        } catch {
            await MainActor.run {
                task.state = .failed(error.localizedDescription)
                task.recording.isTranscribing = false
            }
        }
    }

    private func cleanupCompleted() {
        tasks.removeAll { $0.state == .completed || $0.state == .cancelled }
    }
}
