import SwiftUI

struct BrowseView: View {
    private enum MediaFilter: String, CaseIterable, Identifiable {
        case movies
        case tv
        case all
        case downloaded

        var id: Self { self }
        var title: String {
            switch self {
            case .movies: "Movies"
            case .tv: "TV"
            case .all: "All"
            case .downloaded: "On my device"
            }
        }
    }

    @ObservedObject var session: JellyfinSession
    @ObservedObject var seerrSession: SeerrSession
    @EnvironmentObject private var downloads: OfflineDownloadManager
    @EnvironmentObject private var favourites: FavouritesManager
    @State private var resume: [JellyfinItem] = []
    @State private var nextUp: [JellyfinItem] = []
    @State private var discovery: [String: [SeerrMedia]] = [:]
    @State private var movieGenres: [SeerrGenre] = []
    @State private var tvGenres: [SeerrGenre] = []
    @State private var movieGenreItems: [Int: [SeerrMedia]] = [:]
    @State private var tvGenreItems: [Int: [SeerrMedia]] = [:]
    @State private var error: String?
    @State private var showServices = false
    @State private var showPendingRequests = false
    @State private var showStorage = false
    @State private var hasLoaded = false
    @State private var mediaFilter: MediaFilter = .all
    @State private var serverReachable = true
    @State private var selectedDownloadedItem: JellyfinItem?

    private let discoverySections = [
        ("Trending Movies", "trendingMovies"),
        ("Trending TV", "trendingTV"),
        ("Popular Movies", "popularMovies"),
        ("Popular TV", "popularTV"),
        ("Upcoming Movies", "upcomingMovies"),
        ("Upcoming TV", "upcomingTV"),
    ]

    var body: some View {
        NavigationStack {
            List {
                if session.isRescanningLibraries {
                    Section("Rescanning Libraries") {
                        HStack(spacing: 12) {
                            ProgressView(value: session.libraryRescanProgress)
                            Text(session.libraryRescanProgress, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                if showsDownloadedGrid {
                    if filteredDownloaded.isEmpty {
                        ContentUnavailableView(
                            "No media on my device",
                            systemImage: "tray",
                            description: Text("Movies and episodes saved to your device will appear here and can be watched offline.")
                        )
                    } else {
                        Section("On my device") {
                            AdaptiveMediaGrid(
                                items: filteredDownloaded,
                                detailStyle: { $0.type == "Episode" ? .remainingTime : .runtime },
                                onSelect: { selectedDownloadedItem = $0 }
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                } else {
                    if !filteredDownloaded.isEmpty {
                        Section("On my device") {
                            MiniMediaCarousel(items: filteredDownloaded)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }

                    if !filtered(resume).isEmpty {
                        Section("Continue Watching") {
                            MediaCarousel(items: filtered(resume), detailStyle: .remainingTime)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }

                    if !filtered(favourites.items(for: session.account)).isEmpty {
                        Section("Favourites") {
                            MiniMediaCarousel(items: filtered(favourites.items(for: session.account)))
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }

                    if !filtered(nextUp).isEmpty {
                        Section("Next Up") {
                            MediaCarousel(items: filtered(nextUp), detailStyle: .nextUp)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }

                    ForEach(discoverySections, id: \.1) { section in
                        if let items = discovery[section.1], !filtered(items).isEmpty {
                            Section(section.0) {
                                SeerrMediaCarousel(items: filtered(items), session: seerrSession)
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        }
                    }

                    ForEach(movieGenres) { genre in
                        SeerrGenreBrowseSection(
                            genre: genre,
                            mediaType: .movie,
                            session: seerrSession,
                            items: filtered(movieGenreItems[genre.id] ?? [])
                        )
                    }

                    ForEach(tvGenres) { genre in
                        SeerrGenreBrowseSection(
                            genre: genre,
                            mediaType: .tv,
                            session: seerrSession,
                            items: filtered(tvGenreItems[genre.id] ?? [])
                        )
                    }

                    if resume.isEmpty && nextUp.isEmpty && error == nil && filteredDownloaded.isEmpty {
                        ContentUnavailableView(
                            "Nothing to continue",
                            systemImage: "play.circle",
                            description: Text("Start a movie or show and it will appear here.")
                        )
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
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Content", selection: $mediaFilter) {
                            Text(MediaFilter.all.title).tag(MediaFilter.all)
                            Text(MediaFilter.downloaded.title).tag(MediaFilter.downloaded)
                            Text(MediaFilter.movies.title).tag(MediaFilter.movies)
                            Text(MediaFilter.tv.title).tag(MediaFilter.tv)
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

                        Button { Task { await session.rescanLibraries() } } label: {
                            Label(
                                session.isRescanningLibraries ? "Rescanning..." : "Rescan Libraries",
                                systemImage: "arrow.trianglehead.2.clockwise"
                            )
                        }
                        .disabled(!session.canViewStorage || session.isRescanningLibraries)
                        
                        if seerrSession.isConnected {
                            Divider()

                            Button { showPendingRequests = true } label: {
                                Label(
                                    "Requests",
                                    systemImage: seerrSession.pendingApprovalCount > 0 ? "envelope.open" : "envelope"
                                )
                            }
                            .disabled(!session.isReachable)
                        }

                        Divider()

                        Button(role: .destructive) {
                            seerrSession.disconnect()
                            session.logout()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
            .navigationTitle(serverReachable ? "Browse" : "Offline")
            .toolbarTitleDisplayMode(.inlineLarge)
            .onAppear { startInitialLoad() }
            .refreshable { await load(force: true) }
            .sheet(isPresented: $showServices) {
                ServicesView(jellyfinSession: session, seerrSession: seerrSession)
            }
            .sheet(isPresented: $showPendingRequests) { PendingRequestsView(session: seerrSession) }
            .sheet(isPresented: $showStorage) { StorageView(session: session) }
            .onChange(of: seerrSession.account) { _, _ in
                if seerrSession.api == nil {
                    discovery = [:]
                    movieGenres = []
                    tvGenres = []
                    movieGenreItems = [:]
                    tvGenreItems = [:]
                } else {
                    Task { await loadSeerr() }
                }
            }
        }
    }

    private func load(force: Bool = false) async {
        guard force || !hasLoaded else { return }
        hasLoaded = true
        guard let api = session.api else { return }
        error = nil
        let reachability = await session.refreshReachability()
        serverReachable = reachability == .reachable
        guard reachability != .unauthorized else { return }
        guard serverReachable else {
            resume = []
            nextUp = []
            discovery = [:]
            movieGenres = []
            tvGenres = []
            return
        }
        if let account = session.account { await downloads.syncQueuedProgress(account: account) }

        async let resumeRequest = api.resumeItems()
        async let nextUpRequest = api.nextUpEpisodes()

        do {
            resume = try await resumeRequest
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }

        do {
            nextUp = try await nextUpRequest
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }

        await loadSeerr()
    }

    private func startInitialLoad() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await load(force: true) }
    }

    private func loadSeerr() async {
        guard let api = seerrSession.api else { return }
        async let trendingMovies = api.trendingMovies()
        async let trendingTV = api.trendingTV()
        async let popularMovies = api.popularMovies()
        async let popularTV = api.popularTV()
        async let upcomingMovies = api.upcomingMovies()
        async let upcomingTV = api.upcomingTV()
        async let movieGenreRequest = api.movieGenres()
        async let tvGenreRequest = api.tvGenres()

        if let value = try? await trendingMovies { discovery["trendingMovies"] = value }
        if let value = try? await trendingTV { discovery["trendingTV"] = value }
        if let value = try? await popularMovies { discovery["popularMovies"] = value }
        if let value = try? await popularTV { discovery["popularTV"] = value }
        if let value = try? await upcomingMovies { discovery["upcomingMovies"] = value }
        if let value = try? await upcomingTV { discovery["upcomingTV"] = value }
        movieGenres = (try? await movieGenreRequest) ?? []
        tvGenres = (try? await tvGenreRequest) ?? []

        await loadGenreRows(api: api)
    }

    private func loadGenreRows(api: SeerrAPI) async {
        movieGenreItems = [:]
        tvGenreItems = [:]

        await withTaskGroup(of: (Bool, Int, [SeerrMedia]).self) { group in
            for genre in movieGenres {
                group.addTask {
                    (true, genre.id, (try? await api.movies(genre: genre)) ?? [])
                }
            }
            for genre in tvGenres {
                group.addTask {
                    (false, genre.id, (try? await api.tv(genre: genre)) ?? [])
                }
            }

            for await (isMovie, genreID, items) in group where !items.isEmpty {
                if isMovie { movieGenreItems[genreID] = items }
                else { tvGenreItems[genreID] = items }
            }
        }
    }

    private func filtered(_ items: [JellyfinItem]) -> [JellyfinItem] {
        switch mediaFilter {
        case .all: items
        case .movies: items.filter { $0.type == "Movie" }
        case .tv: items.filter { $0.type != "Movie" }
        case .downloaded: []
        }
    }

    private func filtered(_ items: [SeerrMedia]) -> [SeerrMedia] {
        switch mediaFilter {
        case .all: items
        case .movies: items.filter { !$0.isTV }
        case .tv: items.filter(\.isTV)
        case .downloaded: []
        }
    }

    private var filteredDownloaded: [JellyfinItem] {
        let items = downloads.downloadedItems(for: session.account)
        switch mediaFilter {
        case .movies: return items.filter { $0.type == "Movie" }
        case .tv: return items.filter { $0.type == "Episode" }
        case .all, .downloaded: return items
        }
    }

    private var showsDownloadedGrid: Bool {
        mediaFilter == .downloaded || !serverReachable
    }
}
