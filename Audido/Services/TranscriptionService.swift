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
    private var whisperKit: WhisperKit?

    func loadModel(from folder: String) async throws {
        whisperKit = try await WhisperKit(modelFolder: folder)
        isModelLoaded = true
    }

    func transcribe(
        audioURL: URL,
        language: String = "nl",
        conversationMode: Bool = false,
        onProgress: @escaping (Double, String) -> Void,
        cancelCheck: @escaping () -> Bool
    ) async throws -> String {
        guard let whisperKit else { throw TranscriptionError.noModelLoaded }

        let options = DecodingOptions(
            language: language == "auto" ? nil : language,
            wordTimestamps: conversationMode
        )

        // Get total audio duration for progress calculation
        let audioFile = try AVAudioFile(forReading: audioURL)
        let totalDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options,
            callback: { progress in
                if cancelCheck() { return false }

                // Calculate progress based on window position vs total audio duration
                let processedSeconds = Double(progress.windowId + 1) * 30.0
                let pct = min(processedSeconds / max(totalDuration, 1.0), 1.0)

                Task { @MainActor in
                    onProgress(pct, "Transcribing... \(Int(pct * 100))%")
                }
                return true
            }
        )

        if cancelCheck() {
            throw TranscriptionError.cancelled
        }

        if conversationMode {
            Task { @MainActor in
                onProgress(0.8, "Identifying speakers...")
            }
            return try await transcribeWithSpeakers(audioURL: audioURL, transcriptionResults: results)
        } else {
            return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
    }

    private func transcribeWithSpeakers(audioURL: URL, transcriptionResults: [TranscriptionResult]) async throws -> String {
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
