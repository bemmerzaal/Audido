import SwiftUI

struct PodcastEpisodeListView: View {
    @Environment(PodcastService.self) private var podcastService
    let podcast: Podcast
    var onSelectEpisode: (PodcastEpisode) -> Void
    var onBack: () -> Void

    var body: some View {
        List {
            if podcastService.isLoadingEpisodes {
                HStack {
                    Spacer()
                    ProgressView("Loading episodes...")
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }

            ForEach(podcastService.episodes) { episode in
                Button {
                    onSelectEpisode(episode)
                } label: {
                    EpisodeRow(episode: episode)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(podcast.name)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    onBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
        .task {
            await podcastService.loadEpisodes(from: podcast)
        }
        .overlay {
            if let error = podcastService.errorMessage {
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            }
        }
    }
}

struct EpisodeRow: View {
    let episode: PodcastEpisode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(episode.title)
                .fontWeight(.medium)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let date = episode.publishedDate {
                    Text(date, style: .date)
                }
                if let duration = episode.duration {
                    Text("·")
                    Text(duration)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !episode.description.isEmpty {
                Text(episode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
