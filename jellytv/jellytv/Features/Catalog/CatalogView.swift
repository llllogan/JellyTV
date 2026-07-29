import SwiftUI

struct CatalogView: View {
    private enum CatalogFilter: String, CaseIterable, Identifiable {
        case all
        case downloads

        var id: Self { self }

        var title: String {
            switch self {
            case .all: "All"
            case .downloads: "On my device"
            }
        }
    }

    private struct GenreSection: Identifiable {
        let genre: String
        let items: [JellyfinItem]

        var id: String { genre }
    }

    @ObservedObject var session: JellyfinSession
    @ObservedObject var seerrSession: SeerrSession
    @EnvironmentObject private var downloads: OfflineDownloadManager
    @EnvironmentObject private var favourites: FavouritesManager
    let type: String
    let title: String

    @State private var items: [JellyfinItem] = []
    @State private var error: String?
    @State private var showServices = false
    @State private var showPendingRequests = false
    @State private var showStorage = false
    @State private var filter: CatalogFilter = .all
    @State private var selectedDownloadedItem: JellyfinItem?
    @State private var serverReachable = true

    private var downloadedItems: [JellyfinItem] {
        downloads.downloadedItems(for: session.account)
            .filter { type == "Movie" ? $0.type == "Movie" : $0.type == "Episode" }
            .sorted { lhs, rhs in
                if type != "Movie", lhs.seriesName != rhs.seriesName {
                    return (lhs.seriesName ?? "").localizedCaseInsensitiveCompare(rhs.seriesName ?? "") == .orderedAscending
                }
                if lhs.parentIndexNumber != rhs.parentIndexNumber {
                    return (lhs.parentIndexNumber ?? 0) < (rhs.parentIndexNumber ?? 0)
                }
                if lhs.indexNumber != rhs.indexNumber {
                    return (lhs.indexNumber ?? 0) < (rhs.indexNumber ?? 0)
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

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

    private var favouriteItems: [JellyfinItem] {
        favourites.items(for: session.account).filter { item in
            type == "Movie" ? item.type == "Movie" : item.type != "Movie"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if showsDownloadedContent {
                    if downloadedItems.isEmpty {
                        ContentUnavailableView(
                            serverReachable ? "No \(type == "Movie" ? "movies" : "episodes") on my device" : "You're Offline",
                            systemImage: serverReachable ? "arrow.down.circle" : "wifi.slash",
                            description: Text(
                                serverReachable
                                    ? "\(type == "Movie" ? "Movies" : "Episodes") saved to your device will appear here and can be watched offline."
                                    : "Downloaded \(type == "Movie" ? "movies" : "episodes") will appear here."
                            )
                        )
                    } else {
                        Section("On my device") {
                            AdaptiveMediaGrid(
                                items: downloadedItems,
                                detailStyle: { _ in type == "Movie" ? .runtime : .remainingTime },
                                onSelect: { selectedDownloadedItem = $0 }
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                } else {
                    if !favouriteItems.isEmpty {
                        Section("Favourites") {
                            MiniMediaCarousel(items: favouriteItems)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }

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
            }
            .listStyle(.plain)
            .navigationDestination(item: $selectedDownloadedItem) { item in
                ItemDetailView(item: item)
                    .id(item.id)
            }
            .overlay {
                if filter == .all && serverReachable && items.isEmpty && error == nil {
                    ProgressView()
                }
            }
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inlineLarge)
            .task { await load() }
            .refreshable { await load() }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Content", selection: $filter) {
                            Text(CatalogFilter.all.title).tag(CatalogFilter.all)
                            Text(CatalogFilter.downloads.title).tag(CatalogFilter.downloads)
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                    }
                    Menu {
                        Button { showServices = true } label: {
                            Label("Services", systemImage: "cloud")
                        }

                        Button { showStorage = true } label: {
                            Label("Storage", systemImage: "internaldrive")
                        }
                        .disabled(!session.canViewStorage)

                        Divider()

                        Button { showPendingRequests = true } label: {
                            Label(
                                "Requests",
                                systemImage: seerrSession.pendingApprovalCount > 0 ? "envelope.open" : "envelope"
                            )
                        }
                        .disabled(!session.isReachable)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
            .sheet(isPresented: $showServices) {
                ServicesView(jellyfinSession: session, seerrSession: seerrSession)
            }
            .sheet(isPresented: $showPendingRequests) { PendingRequestsView(session: seerrSession) }
            .sheet(isPresented: $showStorage) { StorageView(session: session) }
            .onChange(of: filter) { _, filter in
                guard filter == .all else { return }
                Task { await load() }
            }
        }
    }

    private func load() async {
        guard filter == .all else { return }
        let reachability = await session.refreshReachability()
        serverReachable = reachability == .reachable
        guard reachability != .unauthorized else { return }
        guard serverReachable else {
            items = []
            error = nil
            return
        }
        guard let api = session.api else { return }
        do {
            items = try await api.items(type: type)
            error = nil
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }
    }

    private var showsDownloadedContent: Bool {
        filter == .downloads || !serverReachable
    }
}
