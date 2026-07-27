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
    @State private var resume: [JellyfinItem] = []
    @State private var nextUp: [JellyfinItem] = []
    @State private var discovery: [String: [SeerrMedia]] = [:]
    @State private var movieGenres: [SeerrGenre] = []
    @State private var tvGenres: [SeerrGenre] = []
    @State private var movieGenreItems: [Int: [SeerrMedia]] = [:]
    @State private var tvGenreItems: [Int: [SeerrMedia]] = [:]
    @State private var error: String?
    @State private var showProfile = false
    @State private var showPendingRequests = false
    @State private var hasLoaded = false
    @State private var mediaFilter: MediaFilter = .all
    @State private var serverReachable = true

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
                if !filteredDownloaded.isEmpty {
                    Section("On my device") {
                        DownloadedMediaCarousel(items: filteredDownloaded)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                if serverReachable && mediaFilter != .downloaded {
                    if !filtered(resume).isEmpty {
                        Section("Continue Watching") {
                            MediaCarousel(items: filtered(resume), detailStyle: .remainingTime)
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
                }

                if !serverReachable && filteredDownloaded.isEmpty {
                    ContentUnavailableView("No media on my device", systemImage: "tray", description: Text("Movies and episodes saved to your device will appear here when Jellyfin is unavailable."))
                } else if serverReachable && resume.isEmpty && nextUp.isEmpty && error == nil && filteredDownloaded.isEmpty {
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
            .listStyle(.plain)
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
                    if seerrSession.user?.canApproveRequests == true {
                        PendingRequestsView.ApprovalEnvelopeButton(session: seerrSession) {
                            showPendingRequests = true
                        }
                    }
                    Button { showProfile = true } label: {
                        Image(systemName: "externaldrive.connected.to.line.below")
                    }
                }
            }
            .navigationTitle("Browse")
            .toolbarTitleDisplayMode(.inlineLarge)
            .task { await load() }
            .refreshable { await load(force: true) }
            .sheet(isPresented: $showProfile) {
                ProfileView(jellyfinSession: session, seerrSession: seerrSession)
            }
            .sheet(isPresented: $showPendingRequests) { PendingRequestsView(session: seerrSession) }
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
        let reachability = await api.reachability()
        if reachability == .unauthorized {
            session.handle(JellyfinError.unauthorized)
            return
        }
        serverReachable = reachability == .reachable
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
}
