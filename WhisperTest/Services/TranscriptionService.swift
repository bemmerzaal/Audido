import Foundation
import WhisperKit
import SpeakerKit
import Observation
import AVFoundation

enum TranscriptionError: LocalizedError {
    case noModelLoaded
    case audioLoadFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "No transcription model is loaded. Please download and select a model in Settings."
        case .audioLoadFailed:
            return "Could not load the audio file."
        case .cancelled:
            return "Transcription was cancelled."
        }
    }
}

@Observable
final class TranscriptionService {
    var isModelLoaded = false
    var statusMessage: String?
    var transcriptionProgress: Double = 0
    var isPaused = false
    var isCancelled = false
    var isTranscribing = false
    private var whisperKit: WhisperKit?
    private var speakerKit: SpeakerKit?

    func loadModel(from folder: String) async throws {
        whisperKit = try await WhisperKit(modelFolder: folder)
        isModelLoaded = true
    }

    // MARK: - Transcription Control

    func pauseTranscription() {
        isPaused = true
        statusMessage = "Paused"
    }

    func resumeTranscription() {
        isPaused = false
    }

    func cancelTranscription() {
        isCancelled = true
        isPaused = false // unblock if paused
    }

    func transcribe(audioURL: URL, language: String = "nl", conversationMode: Bool = false) async throws -> String {
        guard let whisperKit else { throw TranscriptionError.noModelLoaded }

        let options = DecodingOptions(
            language: language == "auto" ? nil : language,
            wordTimestamps: conversationMode
        )

        // Get total audio duration for progress calculation
        let audioFile = try AVAudioFile(forReading: audioURL)
        let totalDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        await MainActor.run {
            statusMessage = "Transcribing audio..."
            transcriptionProgress = 0
            isPaused = false
            isCancelled = false
            isTranscribing = true
        }

        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options,
            callback: { [weak self] progress in
                guard let self else { return false }

                // Cancel check
                if self.isCancelled { return false }

                // Pause: spin-wait until resumed or cancelled
                while self.isPaused && !self.isCancelled {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                if self.isCancelled { return false }

                // Calculate progress based on window position vs total audio duration
                // Each window is ~30 seconds, windowId is 0-based
                let processedSeconds = Double(progress.windowId + 1) * 30.0
                let pct = min(processedSeconds / max(totalDuration, 1.0), 1.0)

                Task { @MainActor in
                    self.transcriptionProgress = pct
                    self.statusMessage = "Transcribing... \(Int(pct * 100))%"
                }
                return true
            }
        )

        // Check if cancelled after transcription returns
        if isCancelled {
            await MainActor.run {
                isTranscribing = false
                transcriptionProgress = 0
                statusMessage = nil
            }
            throw TranscriptionError.cancelled
        }

        if conversationMode {
            await MainActor.run {
                transcriptionProgress = 0.8
                statusMessage = "Identifying speakers..."
            }
            let result = try await transcribeWithSpeakers(audioURL: audioURL, transcriptionResults: results)
            await MainActor.run {
                transcriptionProgress = 0
                isTranscribing = false
            }
            return result
        } else {
            let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            await MainActor.run {
                statusMessage = nil
                transcriptionProgress = 0
                isTranscribing = false
            }
            return text
        }
    }

    private func transcribeWithSpeakers(audioURL: URL, transcriptionResults: [TranscriptionResult]) async throws -> String {
        statusMessage = "Identifying speakers..."

        let audioSamples = try loadAudioSamples(from: audioURL)

        let config = PyannoteConfig(download: true, verbose: false)
        let speakerKit = try await SpeakerKit(config)

        let diarizationOptions = PyannoteDiarizationOptions(
            numberOfSpeakers: nil,
            useExclusiveReconciliation: true
        )

        let diarizationResult = try await speakerKit.diarize(
            audioArray: audioSamples,
            options: diarizationOptions
        )

        let speakerSegments = diarizationResult.addSpeakerInfo(
            to: transcriptionResults,
            strategy: .subsegment(betweenWordThreshold: 0.15)
        )

        var formattedText = ""
        var lastSpeaker: Int? = nil

        for segmentGroup in speakerSegments {
            for segment in segmentGroup {
                let currentSpeaker = segment.speaker.speakerId
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                if currentSpeaker != lastSpeaker {
                    let speakerLabel = currentSpeaker.map { "Speaker \($0 + 1)" } ?? "Unknown"
                    if !formattedText.isEmpty { formattedText += "\n\n" }
                    formattedText += "[\(speakerLabel)]\n\(text)"
                    lastSpeaker = currentSpeaker
                } else {
                    formattedText += " \(text)"
                }
            }
        }

        await speakerKit.unloadModels()
        statusMessage = nil

        return formattedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadAudioSamples(from url: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

        guard let converter = AVAudioConverter(from: audioFile.processingFormat, to: format) else {
            throw TranscriptionError.audioLoadFailed
        }

        let frameCount = AVAudioFrameCount(
            Double(audioFile.length) * 16000.0 / audioFile.processingFormat.sampleRate
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw TranscriptionError.audioLoadFailed
        }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            let inputBuffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: 4096)!
            do {
                try audioFile.read(into: inputBuffer)
                outStatus.pointee = inputBuffer.frameLength > 0 ? .haveData : .endOfStream
            } catch {
                outStatus.pointee = .endOfStream
            }
            return inputBuffer
        }

        if let error { throw error }

        guard let channelData = outputBuffer.floatChannelData else {
            throw TranscriptionError.audioLoadFailed
        }

        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
    }

    func unloadModel() {
        whisperKit = nil
        isModelLoaded = false
    }
}
