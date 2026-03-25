import AVFoundation
import ScreenCaptureKit
import Observation
import CoreAudio

@Observable
final class MeetingCaptureService: NSObject {
    var isCapturing = false
    var currentDuration: TimeInterval = 0.0
    var systemAudioLevel: Float = 0.0
    var micAudioLevel: Float = 0.0
    var availableApps: [SCRunningApplication] = []
    var selectedApp: SCRunningApplication?
    var captureAllSystemAudio = true
    var includeMicrophone = true
    var errorMessage: String?

    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var micEngine: AVAudioEngine?
    private var micFile: AVAudioFile?
    private var startTime: Date?
    private var timer: Timer?
    private var systemAudioURL: URL?
    private var micAudioURL: URL?
    private(set) var outputURL: URL?
    var currentFileName: String?

    // MARK: - Fetch available apps

    func fetchAvailableApps() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            await MainActor.run {
                self.availableApps = content.applications
                    .filter { !$0.applicationName.isEmpty }
                    .sorted { $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Could not get screen content: \(error.localizedDescription). Make sure Screen Recording permission is granted in System Settings → Privacy & Security."
            }
        }
    }

    // MARK: - Start capture

    func startCapture(inputDeviceID: AudioDeviceID? = nil) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        let filter: SCContentFilter
        if captureAllSystemAudio {
            // Capture everything except our own app
            let ownApp = content.applications.first { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            let excludedApps = ownApp.map { [$0] } ?? []
            filter = SCContentFilter(display: content.displays.first!, excludingApplications: excludedApps, exceptingWindows: [])
        } else if let app = selectedApp {
            // Capture specific app
            _ = content.windows.filter { $0.owningApplication?.bundleIdentifier == app.bundleIdentifier }
            filter = SCContentFilter(display: content.displays.first!, including: [app], exceptingWindows: [])
        } else {
            throw MeetingCaptureError.noAppSelected
        }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16000
        config.channelCount = 1
        // Minimize video overhead — we only want audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps minimum

        // Prepare output files
        let tempDir = FileManager.default.temporaryDirectory
        let sessionID = UUID().uuidString

        let sysURL = tempDir.appendingPathComponent("meeting-system-\(sessionID).wav")
        let micURL = tempDir.appendingPathComponent("meeting-mic-\(sessionID).wav")

        let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let sysFile = try AVAudioFile(forWriting: sysURL, settings: audioFormat.settings)

        systemAudioURL = sysURL
        micAudioURL = micURL
        audioFile = sysFile

        // Create and start stream
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "meeting.audio", qos: .userInteractive))
        try await stream.startCapture()
        self.stream = stream

        // Start mic capture if enabled
        if includeMicrophone {
            try startMicCapture(to: micURL, format: audioFormat, inputDeviceID: inputDeviceID)
        }

        await MainActor.run {
            self.startTime = Date()
            self.isCapturing = true
            self.currentDuration = 0
            self.errorMessage = nil

            let startDate = Date()
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.currentDuration = Date().timeIntervalSince(startDate)
                }
            }
        }
    }

    // MARK: - Mic capture

    private func startMicCapture(to fileURL: URL, format: AVAudioFormat, inputDeviceID: AudioDeviceID?) throws {
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
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        let converter = AVAudioConverter(from: inputFormat, to: format)!

        micFile = file

        let unsafeFile = file
        let unsafeSelf = self

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            let frameCount = AVAudioFrameCount(format.sampleRate * Double(buffer.frameLength) / inputFormat.sampleRate)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .haveData {
                try? unsafeFile.write(from: convertedBuffer)
            }

            // Mic level
            if let channelData = buffer.floatChannelData?[0] {
                let frames = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frames { sum += channelData[i] * channelData[i] }
                let rms = sqrt(sum / Float(frames))
                let level = min(max(rms * 5, 0), 1)
                Task { @MainActor in unsafeSelf.micAudioLevel = level }
            }
        }

        engine.prepare()
        try engine.start()
        micEngine = engine
    }

    // MARK: - Stop capture

    func stopCapture() async -> (url: URL, duration: TimeInterval)? {
        timer?.invalidate()
        timer = nil

        // Stop stream
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        audioFile = nil

        // Stop mic
        micEngine?.inputNode.removeTap(onBus: 0)
        micEngine?.stop()
        micEngine = nil
        micFile = nil

        let duration = currentDuration

        await MainActor.run {
            self.isCapturing = false
            self.currentDuration = 0
            self.systemAudioLevel = 0
            self.micAudioLevel = 0
            self.startTime = nil
        }

        // Mix system + mic audio into one file
        guard let sysURL = systemAudioURL else { return nil }

        let outputDir = Recording.recordingsDirectory
        let fileName = "meeting-\(UUID().uuidString).wav"
        let finalURL = outputDir.appendingPathComponent(fileName)

        await MainActor.run {
            self.currentFileName = fileName
            self.outputURL = finalURL
        }

        if includeMicrophone, let micURL = micAudioURL {
            do {
                try await mixAudioFiles(system: sysURL, mic: micURL, output: finalURL)
            } catch {
                // Fallback: just use system audio
                try? FileManager.default.copyItem(at: sysURL, to: finalURL)
            }
            // Cleanup temp files
            try? FileManager.default.removeItem(at: sysURL)
            try? FileManager.default.removeItem(at: micURL)
        } else {
            try? FileManager.default.moveItem(at: sysURL, to: finalURL)
        }

        return (finalURL, duration)
    }

    // MARK: - Mix audio files

    private func mixAudioFiles(system: URL, mic: URL, output: URL) async throws {
        let sysFile = try AVAudioFile(forReading: system)
        let micFile = try AVAudioFile(forReading: mic)

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let outputFile = try AVAudioFile(forWriting: output, settings: format.settings)

        let maxFrames = max(sysFile.length, micFile.length)
        let chunkSize: AVAudioFrameCount = 16000 // 1 second chunks

        var position: AVAudioFramePosition = 0
        while position < maxFrames {
            let remaining = AVAudioFrameCount(maxFrames - position)
            let framesToRead = min(chunkSize, remaining)

            let mixBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead)!
            mixBuffer.frameLength = framesToRead

            // Zero the buffer
            if let data = mixBuffer.floatChannelData?[0] {
                for i in 0..<Int(framesToRead) { data[i] = 0 }
            }

            // Add system audio
            if position < sysFile.length {
                let sysBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead)!
                sysFile.framePosition = position
                try sysFile.read(into: sysBuffer, frameCount: min(framesToRead, AVAudioFrameCount(sysFile.length - position)))

                if let dst = mixBuffer.floatChannelData?[0], let src = sysBuffer.floatChannelData?[0] {
                    for i in 0..<Int(sysBuffer.frameLength) {
                        dst[i] += src[i]
                    }
                }
            }

            // Add mic audio
            if position < micFile.length {
                let micBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead)!
                micFile.framePosition = position
                try micFile.read(into: micBuffer, frameCount: min(framesToRead, AVAudioFrameCount(micFile.length - position)))

                if let dst = mixBuffer.floatChannelData?[0], let src = micBuffer.floatChannelData?[0] {
                    for i in 0..<Int(micBuffer.frameLength) {
                        dst[i] += src[i] * 0.8 // Slightly lower mic volume to balance
                    }
                }
            }

            try outputFile.write(from: mixBuffer)
            position += AVAudioFramePosition(framesToRead)
        }
    }
}

// MARK: - SCStreamDelegate

extension MeetingCaptureService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            self.errorMessage = "Stream stopped: \(error.localizedDescription)"
            self.isCapturing = false
        }
    }
}

// MARK: - SCStreamOutput

extension MeetingCaptureService: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let audioFile else { return }

        guard let formatDesc = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }

        let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
        guard let blockBuffer else { return }

        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else { return }

        var data = Data(count: length)
        _ = data.withUnsafeMutableBytes { rawBuffer in
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: rawBuffer.baseAddress!)
        }

        // Write to file
        let sampleRate = asbd.pointee.mSampleRate
        let channels = asbd.pointee.mChannelsPerFrame
        let bytesPerFrame = asbd.pointee.mBytesPerFrame

        guard bytesPerFrame > 0 else { return }
        let frameCount = AVAudioFrameCount(UInt32(length) / UInt32(bytesPerFrame))
        guard frameCount > 0 else { return }

        let srcFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(channels), interleaved: asbd.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0)

        guard let srcFormat else { return }

        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount) else { return }
        srcBuffer.frameLength = frameCount

        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            if srcFormat.isInterleaved {
                memcpy(srcBuffer.floatChannelData?[0], baseAddress, length)
            } else {
                // Non-interleaved: copy per channel
                let framesPerChannel = Int(frameCount)
                for ch in 0..<Int(channels) {
                    if let dst = srcBuffer.floatChannelData?[ch] {
                        let src = baseAddress.advanced(by: ch * framesPerChannel * MemoryLayout<Float>.size)
                        memcpy(dst, src, framesPerChannel * MemoryLayout<Float>.size)
                    }
                }
            }
        }

        // Calculate level from first channel
        if let channelData = srcBuffer.floatChannelData?[0] {
            var sum: Float = 0
            for i in 0..<Int(frameCount) { sum += channelData[i] * channelData[i] }
            let rms = sqrt(sum / Float(frameCount))
            let level = min(max(rms * 5, 0), 1)
            Task { @MainActor [weak self] in self?.systemAudioLevel = level }
        }

        // Convert to mono 16kHz if needed
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

        if srcFormat.sampleRate == targetFormat.sampleRate && srcFormat.channelCount == targetFormat.channelCount {
            try? audioFile.write(from: srcBuffer)
        } else {
            guard let converter = AVAudioConverter(from: srcFormat, to: targetFormat) else { return }
            let ratio = targetFormat.sampleRate / srcFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(frameCount) * ratio)
            guard outputFrameCount > 0, let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else { return }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return srcBuffer
            }

            if outputBuffer.frameLength > 0 {
                try? audioFile.write(from: outputBuffer)
            }
        }
    }
}

// MARK: - Error

enum MeetingCaptureError: LocalizedError {
    case noAppSelected
    case noDisplay
    case captureNotAuthorized

    var errorDescription: String? {
        switch self {
        case .noAppSelected: return "No application selected for capture"
        case .noDisplay: return "No display found"
        case .captureNotAuthorized: return "Screen capture not authorized. Grant permission in System Settings → Privacy & Security → Screen Recording."
        }
    }
}
