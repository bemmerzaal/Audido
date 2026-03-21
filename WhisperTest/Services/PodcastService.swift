import Foundation
import AVFoundation
import AppKit
import Observation

@Observable
final class PodcastService: NSObject {
    var searchResults: [Podcast] = []
    var episodes: [PodcastEpisode] = []
    var isSearching = false
    var isLoadingEpisodes = false
    var isDownloading = false
    var isPaused = false
    var downloadProgress: Double = 0
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var errorMessage: String?

    private let session = URLSession.shared
    private var downloadTask: URLSessionDownloadTask?
    private var resumeData: Data?
    private var downloadContinuation: CheckedContinuation<URL, Error>?
    private var _downloadSession: URLSession?
    private var downloadSession: URLSession {
        if let session = _downloadSession { return session }
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        _downloadSession = session
        return session
    }

    // MARK: - iTunes Search

    func searchPodcasts(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=podcast&limit=20")!

            let (data, _) = try await session.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let results = json?["results"] as? [[String: Any]] ?? []

            searchResults = results.compactMap { item in
                guard let id = item["collectionId"] as? Int,
                      let name = item["collectionName"] as? String,
                      let artist = item["artistName"] as? String,
                      let feedString = item["feedUrl"] as? String,
                      let feedURL = URL(string: feedString) else { return nil }

                let artworkString = item["artworkUrl100"] as? String
                let artworkURL = artworkString.flatMap { URL(string: $0) }

                return Podcast(id: id, name: name, artistName: artist, artworkURL: artworkURL, feedURL: feedURL)
            }
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
        }

        isSearching = false
    }

    // MARK: - RSS Feed Parsing

    func loadEpisodes(from podcast: Podcast) async {
        isLoadingEpisodes = true
        episodes = []
        errorMessage = nil

        do {
            let (data, _) = try await session.data(from: podcast.feedURL)
            let parser = RSSParser()
            episodes = parser.parse(data: data)
        } catch {
            errorMessage = "Failed to load episodes: \(error.localizedDescription)"
        }

        isLoadingEpisodes = false
    }

    // MARK: - Download & Convert

    func downloadAndConvert(episode: PodcastEpisode) async throws -> URL {
        await MainActor.run {
            isDownloading = true
            isPaused = false
            downloadProgress = 0
            downloadedBytes = 0
            totalBytes = 0
            errorMessage = nil
            resumeData = nil
        }

        // Download MP3 using URLSessionDownloadTask (fast + pause/resume/cancel)
        let tempURL = try await downloadWithTask(from: episode.audioURL)

        // Convert to 16kHz mono WAV for WhisperKit
        let outputDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PodcastAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let outputURL = outputDir.appendingPathComponent("\(episode.id.hashValue).wav")
        try? FileManager.default.removeItem(at: outputURL)

        await MainActor.run { downloadProgress = 0.9 }
        try await convertToWAV(input: tempURL, output: outputURL)
        try? FileManager.default.removeItem(at: tempURL)

        await MainActor.run {
            isDownloading = false
            downloadProgress = 0
        }

        return outputURL
    }

    /// Convert an imported audio file (MP3, M4A, etc.) to 16kHz WAV
    func convertImportedFile(at sourceURL: URL) async throws -> URL {
        await MainActor.run {
            isDownloading = true
            isPaused = false
            downloadProgress = 0.5
            errorMessage = nil
        }

        let outputDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let outputURL = outputDir.appendingPathComponent("\(UUID().uuidString).wav")

        try await convertToWAV(input: sourceURL, output: outputURL)

        await MainActor.run {
            isDownloading = false
            downloadProgress = 0
        }

        return outputURL
    }

    // MARK: - Download Control

    func pauseDownload() {
        downloadTask?.cancel(byProducingResumeData: { [weak self] data in
            Task { @MainActor in
                self?.resumeData = data
                self?.isPaused = true
            }
        })
    }

    func resumeDownload() {
        guard let data = resumeData else { return }
        isPaused = false
        let task = downloadSession.downloadTask(withResumeData: data)
        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        resumeData = nil
        downloadContinuation?.resume(throwing: CancellationError())
        downloadContinuation = nil

        Task { @MainActor in
            isDownloading = false
            isPaused = false
            downloadProgress = 0
            downloadedBytes = 0
            totalBytes = 0
        }
    }

    // MARK: - Private

    private func downloadWithTask(from url: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            self.downloadContinuation = continuation
            let task = downloadSession.downloadTask(with: url)
            self.downloadTask = task
            task.resume()
        }
    }

    private func convertToWAV(input: URL, output: URL) async throws {
        let asset = AVURLAsset(url: input)
        let reader = try AVAssetReader(asset: asset)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw PodcastError.noAudioTrack
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(trackOutput)

        guard reader.startReading() else {
            throw PodcastError.conversionFailed(reader.error?.localizedDescription ?? "Unknown error")
        }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: true)!
        let audioFile = try AVAudioFile(forWriting: output, settings: format.settings)

        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            _ = data.withUnsafeMutableBytes { rawBuffer in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: rawBuffer.baseAddress!)
            }

            let frameCount = AVAudioFrameCount(length / MemoryLayout<Float>.size)
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { continue }
            pcmBuffer.frameLength = frameCount

            data.withUnsafeBytes { rawBuffer in
                let src = rawBuffer.bindMemory(to: Float.self)
                if let dst = pcmBuffer.floatChannelData?[0] {
                    for i in 0..<Int(frameCount) {
                        dst[i] = src[i]
                    }
                }
            }

            try audioFile.write(from: pcmBuffer)
        }

        await MainActor.run { downloadProgress = 1.0 }
    }
}

// MARK: - URLSessionDownloadDelegate

extension PodcastService: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move file to a persistent temp location before the system cleans it up
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            downloadContinuation?.resume(returning: dest)
        } catch {
            downloadContinuation?.resume(throwing: error)
        }
        downloadContinuation = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            self.downloadedBytes = totalBytesWritten
            self.totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 0
            if totalBytesExpectedToWrite > 0 {
                // 0-0.85 for download, 0.85-1.0 for conversion
                self.downloadProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 0.85
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let nsError = error as NSError
            // Don't report cancellation from pause
            if nsError.code == NSURLErrorCancelled, resumeData != nil {
                return
            }
            if nsError.code == NSURLErrorCancelled {
                return // User cancelled
            }
            downloadContinuation?.resume(throwing: error)
            downloadContinuation = nil
        }
    }
}

// MARK: - Errors

enum PodcastError: LocalizedError {
    case noAudioTrack
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "No audio track found in the file."
        case .conversionFailed(let reason):
            return "Audio conversion failed: \(reason)"
        }
    }
}

// MARK: - RSS Parser

private class RSSParser: NSObject, XMLParserDelegate {
    private var episodes: [PodcastEpisode] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentGuid = ""
    private var currentAudioURL: URL?
    private var currentPubDate: String = ""
    private var currentDuration: String?
    private var insideItem = false

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    func parse(data: Data) -> [PodcastEpisode] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return episodes
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName

        if elementName == "item" {
            insideItem = true
            currentTitle = ""
            currentDescription = ""
            currentGuid = ""
            currentAudioURL = nil
            currentPubDate = ""
            currentDuration = nil
        }

        if elementName == "enclosure", insideItem {
            if let urlString = attributes["url"], let url = URL(string: urlString) {
                let type = attributes["type"] ?? ""
                if type.contains("audio") || urlString.hasSuffix(".mp3") || urlString.hasSuffix(".m4a") {
                    currentAudioURL = url
                }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "description": currentDescription += string
        case "guid": currentGuid += string
        case "pubDate": currentPubDate += string
        case "itunes:duration": currentDuration = (currentDuration ?? "") + string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "item", insideItem {
            insideItem = false
            if let audioURL = currentAudioURL {
                let episode = PodcastEpisode(
                    id: currentGuid.isEmpty ? UUID().uuidString : currentGuid.trimmingCharacters(in: .whitespacesAndNewlines),
                    title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: cleanHTML(currentDescription.trimmingCharacters(in: .whitespacesAndNewlines)),
                    publishedDate: dateFormatter.date(from: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)),
                    duration: currentDuration?.trimmingCharacters(in: .whitespacesAndNewlines),
                    audioURL: audioURL
                )
                episodes.append(episode)
            }
        }

        if elementName != "item" {
            currentElement = ""
        }
    }

    private func cleanHTML(_ string: String) -> String {
        guard let data = string.data(using: .utf8),
              let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) else {
            return string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        return attributed.string
    }
}
