import SwiftUI

struct SeerrMediaCarousel: View {
    let items: [SeerrMedia]
    let requestStatuses: [Int: String]
    @ObservedObject var session: SeerrSession

    init(items: [SeerrMedia], session: SeerrSession, requestStatuses: [Int: String] = [:]) {
        self.items = items; self.session = session; self.requestStatuses = requestStatuses
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(items) { item in
                    NavigationLink { SeerrMediaDetailView(media: item, session: session).id(item.requestableID) } label: {
                        SeerrMediaCard(media: item, status: requestStatuses[item.requestableID])
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .scrollTargetLayout().padding(.horizontal, 16).padding(.vertical, 4)
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .scrollIndicators(.hidden).scrollTargetBehavior(.viewAligned)
    }
}

struct SeerrMediaCard: View {
    let media: SeerrMedia
    let status: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: media.artworkURL) { $0.resizable().scaledToFill() } placeholder: {
                Color.gray.opacity(0.18).overlay(Image(systemName: "film"))
            }
            .frame(width: 132, height: 198).clipShape(RoundedRectangle(cornerRadius: 8))
            Text(status ?? (media.isAvailable ? "In library" : (media.releaseText ?? "Requestable")))
                .font(.caption).foregroundStyle(status == nil ? Color.secondary : Color.orange).lineLimit(1)
        }
        .padding(8).frame(width: 148).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel(media.displayTitle)
    }
}

struct SeerrSearchRow: View {
    let media: SeerrMedia
    @ObservedObject var session: SeerrSession
    var body: some View {
        NavigationLink { SeerrMediaDetailView(media: media, session: session).id(media.requestableID) } label: {
            HStack(spacing: 12) {
                AsyncImage(url: media.artworkURL) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.18) }
                    .frame(width: 70, height: 100).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(media.displayTitle).font(.headline)
                    Text(media.isTV ? "TV show" : "Movie").foregroundStyle(.secondary)
                    Text(media.isAvailable ? "Available in your library" : "Request")
                        .font(.caption).foregroundStyle(media.isAvailable ? .green : .accentColor)
                }
            }.padding(.vertical, 3)
        }
    }
}

struct SeerrMediaDetailView: View {
    let media: SeerrMedia
    @ObservedObject var session: SeerrSession
    @EnvironmentObject private var jellyfinSession: JellyfinSession
    @State private var movie: SeerrMovieDetails?
    @State private var show: SeerrTVDetails?
    @State private var submittedStatus: String?
    @State private var error: String?
    @State private var isRequesting = false
    @State private var selectedSeasonNumbers = Set<Int>()
    @State private var locallyPendingSeasonNumbers = Set<Int>()
    @State private var librarySeasonNumbers = Set<Int>()

    private var isTV: Bool { media.isTV }
    private var title: String { movie?.title ?? show?.name ?? media.displayTitle }
    private var overview: String? { movie?.overview ?? show?.overview ?? media.overview }
    private var artwork: URL? {
        let path = movie?.posterPath ?? show?.posterPath
        return path.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") } ?? media.artworkURL
    }
    private var isAvailable: Bool { (movie?.mediaInfo?.status ?? show?.mediaInfo?.status ?? media.mediaInfo?.status ?? media.status) == 5 }
    private var existingStatus: String? {
        submittedStatus ?? movie?.mediaInfo?.requests?.first?.statusText
    }
    private var requestableSeasons: [SeerrSeason] { (show?.seasons ?? []).filter { $0.seasonNumber > 0 } }
    private var selectedSeasonTitle: String {
        selectedSeasonNumbers.count == 1 ? "Request 1 season" : "Request \(selectedSeasonNumbers.count) seasons"
    }

    var body: some View {
        Group {
            if isTV {
                tvDetail
            } else {
                movieDetail
            }
        }
        .navigationTitle(isTV ? "Show" : "Movie")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: media.requestableID) { await load() }
    }

    private var movieDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncImage(url: artwork) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.18) }
                    .frame(width: 180, height: 270).clipShape(RoundedRectangle(cornerRadius: 10)).frame(maxWidth: .infinity)
                Text(title).font(.title.bold())
                if let release = movie?.releaseDate ?? show?.firstAirDate ?? media.releaseText { Text(release).foregroundStyle(.secondary) }
                requestArea
                if let overview { Text(overview).foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.red) }
            }.padding()
        }
    }

    private var tvDetail: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    AsyncImage(url: artwork) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.18) }
                        .frame(width: 180, height: 270)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: .infinity)
                    Text(title).font(.title.bold())
                    if let release = show?.firstAirDate ?? media.releaseText { Text(release).foregroundStyle(.secondary) }
                    if let overview { Text(overview).foregroundStyle(.secondary) }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                .padding(.bottom)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color(uiColor: .systemBackground))

            if !requestableSeasons.isEmpty {
                Section {
                    ForEach(requestableSeasons, id: \.stableID) { season in
                        seasonRow(season)
                    }

                    Button { Task { await requestSelectedSeasons() } } label: {
                        Text(isRequesting ? "Requesting…" : selectedSeasonTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedSeasonNumbers.isEmpty || isRequesting)
                }
                .listRowBackground(Color(uiColor: .secondarySystemBackground))
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
    }

    private enum SeasonState {
        case available
        case pending
        case selectable(isSelected: Bool)
    }

    @ViewBuilder private func seasonRow(_ season: SeerrSeason) -> some View {
        let state = seasonState(for: season)
        Button {
            guard case let .selectable(isSelected) = state else { return }
            if isSelected {
                selectedSeasonNumbers.remove(season.seasonNumber)
            } else {
                selectedSeasonNumbers.insert(season.seasonNumber)
            }
        } label: {
            HStack {
                Text(season.name ?? "Season \(season.seasonNumber)")
                Spacer()
                seasonStatusSymbol(for: state)
            }
        }
        .buttonStyle(.plain)
        .disabled(isSeasonUnavailable(state))
        .animation(.default, value: selectedSeasonNumbers)
    }

    @ViewBuilder private var requestArea: some View {
        if isAvailable {
            Label("Available in your library", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else if let existingStatus {
            Label(existingStatus, systemImage: "clock.fill").foregroundStyle(.orange)
        } else {
            Button { Task { await request() } } label: {
                Label(isRequesting ? "Requesting…" : "Request", systemImage: "plus")
                    .padding(.horizontal, 14)
                    .frame(height: 32)
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isRequesting)
        }
    }

    private func load() async {
        guard let api = session.api else { return }
        movie = nil
        show = nil
        submittedStatus = nil
        selectedSeasonNumbers = []
        locallyPendingSeasonNumbers = []
        librarySeasonNumbers = []
        error = nil
        do {
            if isTV {
                let details = try await api.tv(id: media.requestableID)
                show = details
                await loadLibrarySeasons(for: details)
            } else {
                movie = try await api.movie(id: media.requestableID)
            }
        } catch { session.handle(error); self.error = error.localizedDescription }
    }

    private func loadLibrarySeasons(for details: SeerrTVDetails) async {
        guard let mediaID = details.mediaInfo?.jellyfinMediaID,
              let api = jellyfinSession.api,
              let seasons = try? await api.children(parentID: mediaID, type: "Season")
        else { return }

        librarySeasonNumbers = Set(seasons.compactMap(\.indexNumber))
    }

    private func request() async {
        guard let api = session.api else { return }
        isRequesting = true; error = nil
        defer { isRequesting = false }
        do {
            let response = try await api.requestMovie(id: media.requestableID)
            submittedStatus = response.statusText
        } catch { session.handle(error); self.error = error.localizedDescription }
    }

    private func seasonState(for season: SeerrSeason) -> SeasonState {
        let mediaStatus = libraryStatus(for: season)
        if librarySeasonNumbers.contains(season.seasonNumber) || show?.mediaInfo?.status == 5 || mediaStatus == 5 {
            return .available
        }
        if locallyPendingSeasonNumbers.contains(season.seasonNumber) || isLibraryInProgress(mediaStatus) || isRequestPending(requestStatus(for: season)) {
            return .pending
        }
        return .selectable(isSelected: selectedSeasonNumbers.contains(season.seasonNumber))
    }

    private func libraryStatus(for season: SeerrSeason) -> Int? {
        show?.mediaInfo?.seasons?.first(where: { $0.seasonNumber == season.seasonNumber })?.status
    }

    private func requestStatus(for season: SeerrSeason) -> Int? {
        let requests = (show?.mediaInfo?.requests ?? []) + (season.mediaInfo?.requests ?? [])
        for request in requests.reversed() {
            guard let requestedSeason = request.seasons?.first(where: { $0.seasonNumber == season.seasonNumber }) else { continue }
            return requestedSeason.status ?? request.status
        }
        return nil
    }

    private func isLibraryInProgress(_ status: Int?) -> Bool {
        status == 2 || status == 3 || status == 4
    }

    private func isRequestPending(_ status: Int?) -> Bool {
        status == 1 || status == 2
    }

    private func isSeasonUnavailable(_ state: SeasonState) -> Bool {
        switch state {
        case .selectable: false
        case .available, .pending: true
        }
    }

    @ViewBuilder private func seasonStatusSymbol(for state: SeasonState) -> some View {
        switch state {
        case .available:
            Image(systemName: "checkmark")
                .fontWeight(.bold)
                .foregroundStyle(.green)
        case .pending:
            Text("Pending")
                .font(.subheadline)
                .foregroundStyle(.orange)
        case let .selectable(isSelected):
            if isSelected {
                Image(systemName: "checkmark.circle")
                    .fontWeight(.bold)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(.tint)
            } else {
                Image(systemName: "circle")
                    .fontWeight(.bold)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func requestSelectedSeasons() async {
        guard let api = session.api else { return }
        let seasons = selectedSeasonNumbers.sorted()
        isRequesting = true
        error = nil
        defer { isRequesting = false }
        do {
            _ = try await api.requestTV(id: media.requestableID, seasons: seasons)
            locallyPendingSeasonNumbers.formUnion(seasons)
            selectedSeasonNumbers = []
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }
    }
}
