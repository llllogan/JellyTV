import SwiftUI

struct CatalogView: View {
    private struct GenreSection: Identifiable {
        let genre: String
        let items: [JellyfinItem]

        var id: String { genre }
    }

    @ObservedObject var session: JellyfinSession
    let type: String
    let title: String

    @State private var items: [JellyfinItem] = []
    @State private var error: String?

    private var genreSections: [GenreSection] {
        var grouped: [String: [JellyfinItem]] = [:]

        for item in items {
            let genres: [String]
            if let itemGenres = item.genres, !itemGenres.isEmpty {
                genres = itemGenres
            } else {
                genres = ["Other"]
            }
            for genre in genres {
                grouped[genre, default: []].append(item)
            }
        }

        return grouped
            .map { GenreSection(genre: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.genre.localizedCaseInsensitiveCompare($1.genre) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(genreSections) { section in
                    Section(section.genre) {
                        MediaCarousel(items: section.items)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .listStyle(.plain)
            .overlay {
                if items.isEmpty && error == nil {
                    ProgressView()
                }
            }
            .navigationTitle(title)
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard let api = session.api else { return }
        do {
            items = try await api.items(type: type)
            error = nil
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }
    }
}
