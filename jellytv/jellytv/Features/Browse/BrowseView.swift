import SwiftUI

struct BrowseView: View {
    @ObservedObject var session: JellyfinSession
    @ObservedObject var seerrSession: SeerrSession
    @State private var resume: [JellyfinItem] = []
    @State private var nextUp: [JellyfinItem] = []
    @State private var pending: [SeerrRequest] = []
    @State private var discovery: [String: [SeerrMedia]] = [:]
    @State private var error: String?
    @State private var showSeerrConnection = false

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
                if !resume.isEmpty {
                    Section("Continue Watching") {
                        MediaCarousel(items: resume, detailStyle: .remainingTime)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                if !nextUp.isEmpty {
                    Section("Next Up") {
                        MediaCarousel(items: nextUp, detailStyle: .nextUp)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                if !pending.isEmpty {
                    Section("Pending Requests") {
                        SeerrMediaCarousel(
                            items: pending.compactMap(\.media),
                            session: seerrSession,
                            requestStatuses: Dictionary(uniqueKeysWithValues: pending.compactMap { request in
                                request.media.map { ($0.requestableID, request.statusText) }
                            })
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                ForEach(discoverySections, id: \.1) { section in
                    if let items = discovery[section.1], !items.isEmpty {
                        Section(section.0) {
                            SeerrMediaCarousel(items: items, session: seerrSession)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                }

                if resume.isEmpty && nextUp.isEmpty && error == nil {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") {
                        seerrSession.disconnect()
                        session.logout()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(seerrSession.isConnected ? "Seerr" : "Connect Seerr") { showSeerrConnection = true }
                }
            }
            .navigationTitle("Browse")
            .task { await load() }
            .sheet(isPresented: $showSeerrConnection) { SeerrConnectionView(session: seerrSession) }
        }
    }

    private func load() async {
        guard let api = session.api else { return }
        error = nil

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
        async let pendingRequest = api.pendingRequests()
        async let trendingMovies = api.trendingMovies()
        async let trendingTV = api.trendingTV()
        async let popularMovies = api.popularMovies()
        async let popularTV = api.popularTV()
        async let upcomingMovies = api.upcomingMovies()
        async let upcomingTV = api.upcomingTV()

        if let value = try? await pendingRequest { pending = value.filter { $0.status != 5 } }
        if let value = try? await trendingMovies { discovery["trendingMovies"] = value }
        if let value = try? await trendingTV { discovery["trendingTV"] = value }
        if let value = try? await popularMovies { discovery["popularMovies"] = value }
        if let value = try? await popularTV { discovery["popularTV"] = value }
        if let value = try? await upcomingMovies { discovery["upcomingMovies"] = value }
        if let value = try? await upcomingTV { discovery["upcomingTV"] = value }
    }
}
