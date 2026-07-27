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
    let type: String
    let title: String

    @State private var items: [JellyfinItem] = []
    @State private var error: String?
    @State private var showProfile = false
    @State private var showPendingRequests = false
    @State private var filter: CatalogFilter = .all

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

    var body: some View {
        NavigationStack {
            List {
                if filter == .downloads {
                    if downloadedItems.isEmpty {
                        ContentUnavailableView(
                            "No \(type == "Movie" ? "movies" : "episodes") on my device",
                            systemImage: "arrow.down.circle",
                            description: Text("\(type == "Movie" ? "Movies" : "Episodes") saved to your device will appear here and can be watched offline.")
                        )
                    } else {
                        Section("On my device") {
                            DownloadedMediaCarousel(items: downloadedItems)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                } else {
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
            .overlay {
                if filter == .all && items.isEmpty && error == nil {
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
            .sheet(isPresented: $showProfile) {
                ProfileView(jellyfinSession: session, seerrSession: seerrSession)
            }
            .sheet(isPresented: $showPendingRequests) { PendingRequestsView(session: seerrSession) }
            .onChange(of: filter) { _, filter in
                guard filter == .all else { return }
                Task { await load() }
            }
        }
    }

    private func load() async {
        guard filter == .all else { return }
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
