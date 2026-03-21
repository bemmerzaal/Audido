import SwiftUI

struct PodcastSearchView: View {
    @Environment(PodcastService.self) private var podcastService
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    var onSelectPodcast: (Podcast) -> Void

    var body: some View {
        List {
            if podcastService.isSearching {
                HStack {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }

            ForEach(podcastService.searchResults) { podcast in
                Button {
                    onSelectPodcast(podcast)
                } label: {
                    PodcastRow(podcast: podcast)
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search podcasts...")
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await podcastService.searchPodcasts(query: newValue)
            }
        }
        .navigationTitle("Podcasts")
        .overlay {
            if !podcastService.isSearching && podcastService.searchResults.isEmpty && searchText.isEmpty {
                ContentUnavailableView(
                    "Search Podcasts",
                    systemImage: "mic.fill",
                    description: Text("Search for a podcast by name to browse and transcribe episodes.")
                )
            } else if !podcastService.isSearching && podcastService.searchResults.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}

struct PodcastRow: View {
    let podcast: Podcast

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: podcast.artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(podcast.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(podcast.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
