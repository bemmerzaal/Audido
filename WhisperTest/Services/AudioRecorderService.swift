import AVFoundation
import Observation

@Observable
final class AudioRecorderService {
    var isRecording = false
    var audioLevel: Float = 0.0
    var currentDuration: TimeInterval = 0.0
    var currentFileName: String?

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var startTime: Date?
    private var timer: Timer?

    func startRecording(to fileURL: URL) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

        let file = try AVAudioFile(forWriting: fileURL, settings: recordingFormat.settings)

        let converter = AVAudioConverter(from: inputFormat, to: recordingFormat)!

        let unsafeFile = file
        nonisolated(unsafe) let unsafeSelf = self

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            let frameCount = AVAudioFrameCount(recordingFormat.sampleRate * Double(buffer.frameLength) / inputFormat.sampleRate)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: recordingFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .haveData {
                try? unsafeFile.write(from: convertedBuffer)
            }

            // Calculate RMS for audio level
            if let channelData = buffer.floatChannelData?[0] {
                let frames = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frames {
                    sum += channelData[i] * channelData[i]
                }
                let rms = sqrt(sum / Float(frames))
                let level = min(max(rms * 5, 0), 1)
                Task { @MainActor in
                    unsafeSelf.audioLevel = level
                }
            }
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        audioFile = file
        startTime = Date()
        isRecording = true
        currentDuration = 0

        let startDate = startTime!
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentDuration = Date().timeIntervalSince(startDate)
            }
        }
    }

    func stopRecording() -> TimeInterval {
        timer?.invalidate()
        timer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil

        isRecording = false
        let duration = currentDuration
        currentDuration = 0
        audioLevel = 0
        startTime = nil

        return duration
    }
}
