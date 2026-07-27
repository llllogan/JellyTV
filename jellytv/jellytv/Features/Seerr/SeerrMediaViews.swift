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
    @State private var movie: SeerrMovieDetails?
    @State private var show: SeerrTVDetails?
    @State private var submittedStatus: String?
    @State private var error: String?
    @State private var isRequesting = false
    @State private var showSeasonPicker = false

    private var isTV: Bool { media.isTV }
    private var title: String { movie?.title ?? show?.name ?? media.displayTitle }
    private var overview: String? { movie?.overview ?? show?.overview ?? media.overview }
    private var artwork: URL? {
        let path = movie?.posterPath ?? show?.posterPath
        return path.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") } ?? media.artworkURL
    }
    private var isAvailable: Bool { (movie?.mediaInfo?.status ?? show?.mediaInfo?.status ?? media.mediaInfo?.status ?? media.status) == 5 }
    private var existingStatus: String? {
        submittedStatus ?? (movie?.mediaInfo?.requests?.first?.statusText ?? show?.mediaInfo?.requests?.first?.statusText)
    }

    var body: some View {
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
        .navigationTitle(isTV ? "Show" : "Movie").navigationBarTitleDisplayMode(.inline)
        .task(id: media.requestableID) { await load() }
        .sheet(isPresented: $showSeasonPicker) {
            TVSeasonRequestView(
                mediaID: media.requestableID,
                seasons: show?.seasons ?? [],
                session: session
            ) { request in
                submittedStatus = request.statusText
            }
        }
    }

    @ViewBuilder private var requestArea: some View {
        if isAvailable {
            Label("Available in your library", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else if let existingStatus {
            Label(existingStatus, systemImage: "clock.fill").foregroundStyle(.orange)
        } else if isTV {
            Button { showSeasonPicker = true } label: {
                Label("Request", systemImage: "arrow.down")
                    .padding(.horizontal, 14)
                    .frame(height: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        } else {
            Button { Task { await request() } } label: {
                Label(isRequesting ? "Requesting…" : "Request", systemImage: "arrow.down")
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
        error = nil
        do {
            if isTV { show = try await api.tv(id: media.requestableID) }
            else { movie = try await api.movie(id: media.requestableID) }
        } catch { session.handle(error); self.error = error.localizedDescription }
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
}

struct TVSeasonRequestView: View {
    let mediaID: Int
    let seasons: [SeerrSeason]
    @ObservedObject var session: SeerrSession
    let onRequested: (SeerrRequest) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSeasons = Set<Int>()
    @State private var isSubmitting = false
    @State private var error: String?

    private var requestableSeasons: [SeerrSeason] {
        seasons.filter { $0.seasonNumber > 0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Seasons") {
                    ForEach(requestableSeasons, id: \.stableID) { season in
                        Toggle(season.name ?? "Season \(season.seasonNumber)", isOn: Binding(
                            get: { selectedSeasons.contains(season.seasonNumber) },
                            set: { isSelected in
                                if isSelected { selectedSeasons.insert(season.seasonNumber) }
                                else { selectedSeasons.remove(season.seasonNumber) }
                            }
                        ))
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Request Seasons")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(role: .cancel) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .confirm) { Task { await submit() } }
                        .disabled(selectedSeasons.isEmpty || isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        guard let api = session.api else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let request = try await api.requestTV(id: mediaID, seasons: selectedSeasons.sorted())
            onRequested(request)
            dismiss()
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }
    }
}
