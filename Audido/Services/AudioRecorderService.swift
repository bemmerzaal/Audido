import AVFoundation
import AudioToolbox
import CoreAudio
import Accelerate
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
    private var isStopping = false
    private var lastLevelUpdate: CFAbsoluteTime = 0

    func startRecording(to fileURL: URL, inputDeviceID: AudioDeviceID? = nil) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        if let deviceID = inputDeviceID, let audioUnit = inputNode.audioUnit {
            var id = deviceID
            AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)
        let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: fileURL, settings: recordingFormat.settings)
        let converter = AVAudioConverter(from: inputFormat, to: recordingFormat)!

        // Use a dedicated serial queue for file writing to keep audio thread fast
        let writeQueue = DispatchQueue(label: "com.audido.audiowrite", qos: .userInitiated)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Convert and write on background queue
            let frameCount = AVAudioFrameCount(recordingFormat.sampleRate * Double(buffer.frameLength) / inputFormat.sampleRate)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: recordingFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .haveData {
                writeQueue.async {
                    try? file.write(from: convertedBuffer)
                }
            }

            // Throttle audio level updates to ~15fps to avoid flooding the main thread
            let now = CFAbsoluteTimeGetCurrent()
            guard now - self.lastLevelUpdate >= 0.066 else { return }
            self.lastLevelUpdate = now

            // Use vDSP for fast RMS calculation
            if let channelData = buffer.floatChannelData?[0] {
                var rms: Float = 0
                let frames = vDSP_Length(buffer.frameLength)
                vDSP_rmsqv(channelData, 1, &rms, frames)
                let level = min(max(rms * 12, 0), 1)
                DispatchQueue.main.async { [weak self] in
                    self?.audioLevel = level
                }
            }
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        audioFile = file
        startTime = Date()
        isRecording = true
        isStopping = false
        currentDuration = 0

        let startDate = startTime!
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.currentDuration = Date().timeIntervalSince(startDate)
        }
    }

    func stopRecording() -> TimeInterval {
        // Guard against double-stop
        guard isRecording, !isStopping else { return currentDuration }
        isStopping = true

        timer?.invalidate()
        timer = nil

        // Remove tap first, then stop engine
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil

        isRecording = false
        let duration = currentDuration
        currentDuration = 0
        audioLevel = 0
        startTime = nil
        isStopping = false

        return duration
    }
}
