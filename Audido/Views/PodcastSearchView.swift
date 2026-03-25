import SwiftUI

struct PodcastSearchView: View {
    @Environment(PodcastService.self) private var podcastService
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    var onSelectPodcast: (Podcast) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.callout)

                    TextField("podcast.search_placeholder", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 220)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AudidoToolbarButtonMetrics.horizontalPadding)
                .padding(.vertical, AudidoToolbarButtonMetrics.verticalPadding)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
            }
            .padding()

            Divider()

            List {
                if podcastService.isSearching {
                    HStack {
                        Spacer()
                        ProgressView("podcast.searching")
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }

                ForEach(podcastService.searchResults) { podcast in
                    Button {
                        onSelectPodcast(podcast)
                    } label: {
                        PodcastRow(podcast: podcast)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await podcastService.searchPodcasts(query: newValue)
            }
        }
        .navigationTitle("podcast.nav_title")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if !podcastService.isSearching && podcastService.searchResults.isEmpty && searchText.isEmpty {
                ContentUnavailableView(
                    "podcast.search_empty_title",
                    systemImage: "mic.fill",
                    description: Text("podcast.search_empty_description")
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
