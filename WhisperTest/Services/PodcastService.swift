import Foundation
import AVFoundation
import AppKit
import Observation

@Observable
final class PodcastService {
    var searchResults: [Podcast] = []
    var episodes: [PodcastEpisode] = []
    var isSearching = false
    var isLoadingEpisodes = false
    var isDownloading = false
    var downloadProgress: Double = 0
    var errorMessage: String?

    private let session = URLSession.shared

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
        isDownloading = true
        downloadProgress = 0
        errorMessage = nil

        defer {
            Task { @MainActor in
                isDownloading = false
                downloadProgress = 0
            }
        }

        // Download MP3
        let (tempURL, _) = try await downloadWithProgress(from: episode.audioURL)

        // Convert to 16kHz mono WAV for WhisperKit
        let outputDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PodcastAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let outputURL = outputDir.appendingPathComponent("\(episode.id.hashValue).wav")

        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)

        try await convertToWAV(input: tempURL, output: outputURL)

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)

        return outputURL
    }

    private func downloadWithProgress(from url: URL) async throws -> (URL, URLResponse) {
        let (asyncBytes, response) = try await session.bytes(from: url)
        let expectedLength = response.expectedContentLength
        var data = Data()
        if expectedLength > 0 {
            data.reserveCapacity(Int(expectedLength))
        }

        var downloaded: Int64 = 0
        for try await byte in asyncBytes {
            data.append(byte)
            downloaded += 1
            if expectedLength > 0 && downloaded % 65536 == 0 {
                let progress = Double(downloaded) / Double(expectedLength)
                await MainActor.run {
                    self.downloadProgress = min(progress * 0.8, 0.8) // 80% for download, 20% for conversion
                }
            }
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        try data.write(to: tempURL)
        return (tempURL, response)
    }

    private func convertToWAV(input: URL, output: URL) async throws {
        let asset = AVURLAsset(url: input)

        await MainActor.run { downloadProgress = 0.85 }

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

// MARK: - Errors

enum PodcastError: LocalizedError {
    case noAudioTrack
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "No audio track found in the podcast episode."
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
            // Fallback: strip tags with regex
            return string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        return attributed.string
    }
}
