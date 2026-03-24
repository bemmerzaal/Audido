import Foundation

struct Podcast: Identifiable, Hashable {
    let id: Int
    let name: String
    let artistName: String
    let artworkURL: URL?
    let feedURL: URL

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Podcast, rhs: Podcast) -> Bool {
        lhs.id == rhs.id
    }
}

struct PodcastEpisode: Identifiable, Hashable {
    let id: String // guid from RSS
    let title: String
    let description: String
    let publishedDate: Date?
    let duration: String?
    let audioURL: URL

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PodcastEpisode, rhs: PodcastEpisode) -> Bool {
        lhs.id == rhs.id
    }
}
