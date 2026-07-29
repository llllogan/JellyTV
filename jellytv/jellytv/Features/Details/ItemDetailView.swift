import SwiftUI

struct ItemDetailView: View {
    let item: JellyfinItem
    @EnvironmentObject private var player: PlayerCoordinator
    @EnvironmentObject private var session: JellyfinSession
    @EnvironmentObject private var downloads: OfflineDownloadManager
    @EnvironmentObject private var favourites: FavouritesManager
    @EnvironmentObject private var itemDetailCache: ItemDetailCache
    @State private var details: JellyfinItem?
    @State private var children: [JellyfinItem] = []
    @State private var hierarchyParent: JellyfinItem?
    @State private var error: String?
    @State private var serverReachable = false
    @SceneStorage("item-detail-scroll-position") private var savedScrollPosition = ""
    @State private var selectedAudioStreamIndex: Int?
    @State private var favouriteMessage: String?
    @State private var favouriteMessageID = UUID()

    init(item: JellyfinItem) {
        self.item = item
        _savedScrollPosition = SceneStorage(wrappedValue: "", "item-detail-scroll-position-\(item.id)")
    }

    var body: some View {
        List {
            Section {
                let target = details ?? item
                ZStack(alignment: .topLeading) {
                    ArtworkView(
                        item: target,
                        height: nil,
                        fillsFrame: true,
                        cornerRadius: 0
                    )
                    .padding(.top, 50)

                    ArtworkView(
                        item: target,
                        height: nil,
                        fillsFrame: true,
                        cornerRadius: 0
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .scaleEffect(x: 1, y: -1, anchor: .center)
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .frame(height: 50, alignment: .bottom)
                    .clipped()

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.name).font(.title.bold())
                            detailSubtitle(for: target)
                        }

                        actionRow
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 64)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        ZStack {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.75)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            Rectangle()
                                .fill(.thinMaterial)
                                .mask(
                                    LinearGradient(
                                        colors: [.clear, .clear, .black.opacity(0.9)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .environment(\.colorScheme, .dark)

                    LinearGradient(
                        colors: [.black.opacity(0.9), .black.opacity(0.7), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                    .background {
                        Rectangle()
                            .fill(.thinMaterial)
                            .mask(
                                LinearGradient(
                                    colors: [.black.opacity(0.95), .black.opacity(0.75), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                }
                .containerRelativeFrame(.horizontal)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .id("summary")

                if hasSupplementaryDetails(for: target) {
                    VStack(alignment: .leading, spacing: 16) {
                        if case let .downloading(progress) = downloads.state(for: target.id, account: session.account) {
                            Text("Downloading \(Int(progress * 100))% (\(ByteCountFormatter.string(fromByteCount: downloads.downloadedBytes(itemID: target.id, account: session.account), countStyle: .file)))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if case let .failed(message) = downloads.state(for: target.id, account: session.account) {
                            Text(message).font(.footnote).foregroundStyle(.red)
                        }
                        if let error { Text(error).foregroundStyle(.red) }
                        if let overview = target.overview { Text(overview).foregroundStyle(.secondary) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color(uiColor: .systemBackground))
                }
            }
            .listSectionMargins(.horizontal, 0)

            if let hierarchyParent {
                Section {
                    hierarchyRow(hierarchyParent)
                }
                .listRowBackground(Color(uiColor: .secondarySystemBackground))
            }

            if !children.isEmpty {
                Section(item.type == "Season" ? "Episodes" : "Seasons") {
                    ForEach(children) { child in
                        ItemRow(item: child)
                            .id(child.id)
                            .padding(.vertical)
                    }
                }
                .listRowInsets(EdgeInsets())
            }

            let target = details ?? item
            if !metadataItems(for: target).isEmpty {
                Section {
                    ForEach(metadataItems(for: target)) { metadata in
                        HStack {
                            Image(systemName: metadata.systemImage)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(metadata.primaryColor, metadata.secondaryColor)
                                .frame(width: 20)
                            Text(metadata.title)
                            Spacer()
                            Text(metadata.value)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowBackground(Color(uiColor: .secondarySystemBackground))
            }
        }
        .listStyle(.insetGrouped)
        .scrollPosition(id: scrollPosition)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
        .contentMargins(.top, 0, for: .scrollContent)
        .ignoresSafeArea(.container, edges: .top)
        .scrollEdgeEffectHidden(true, for: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                favouriteToolbarTitle
            }

            let target = details ?? item
            if favourites.isSupported(target) {
                ToolbarItem(placement: .topBarTrailing) {
                    if favourites.contains(target, account: session.account) {
                        Button {
                            favourites.unfavourite(target, account: session.account)
                            showFavouriteMessage(for: target, wasAdded: false)
                        } label: {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                        .accessibilityLabel("Remove from favourites")
                    } else if target.type == "Episode" {
                        Menu {
                            Button("Favourite episode") {
                                favourites.favourite(target, account: session.account)
                                showFavouriteMessage(for: target, wasAdded: true)
                            }
                            Button("Favourite season") {
                                Task { await favouriteSeason(for: target) }
                            }
                        } label: {
                            Image(systemName: "star")
                        }
                        .disabled(session.account == nil || target.seasonID == nil)
                        .accessibilityLabel("Add to favourites")
                    } else {
                        Button {
                            favourites.favourite(target, account: session.account)
                            showFavouriteMessage(for: target, wasAdded: true)
                        } label: {
                            Image(systemName: "star")
                        }
                        .disabled(session.account == nil)
                        .accessibilityLabel("Add to favourites")
                    }
                }
            }
        }
        .task(id: item.id) { await load() }
    }

    private var favouriteToolbarTitle: some View {
        ZStack {
            Text(defaultToolbarTitle)
                .frame(width: 230)
                .opacity(favouriteMessage == nil ? 1 : 0)
                .offset(y: favouriteMessage == nil ? 0 : -22)
                .rotation3DEffect(
                    .degrees(favouriteMessage == nil ? 0 : -80),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .bottom
                )

            if let favouriteMessage {
                Text(favouriteMessage)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: 230)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        )
                    )
            }
        }
        .font(.headline)
        .frame(width: 230, height: 22)
        .clipped()
        .animation(.snappy(duration: 0.35), value: favouriteMessage)
        .frame(width: 230, height: 44)
        .glassEffect(.regular, in: .capsule)
        .accessibilityLabel(favouriteMessage ?? defaultToolbarTitle)
    }

    private var defaultToolbarTitle: String {
        switch (details ?? item).type {
        case "Movie": "Movie"
        case "Series": "Series"
        case "Season": "Season"
        case "Episode": "Episode"
        default: "Details"
        }
    }

    private func showFavouriteMessage(for _: JellyfinItem, wasAdded: Bool) {
        let message = wasAdded ? "Added to favourites" : "Removed from favourites"
        let messageID = UUID()
        favouriteMessageID = messageID

        withAnimation {
            favouriteMessage = message
        }

        Task {
            try? await Task.sleep(for: .seconds(3))
            guard favouriteMessageID == messageID else { return }
            withAnimation {
                favouriteMessage = nil
            }
        }
    }

    private var scrollPosition: Binding<String?> {
        Binding(
            get: { savedScrollPosition.isEmpty ? nil : savedScrollPosition },
            set: { savedScrollPosition = $0 ?? "" }
        )
    }

    private func hasSupplementaryDetails(for target: JellyfinItem) -> Bool {
        if case .downloading = downloads.state(for: target.id, account: session.account) {
            return true
        }
        if case .failed = downloads.state(for: target.id, account: session.account) {
            return true
        }
        return error != nil || target.overview != nil
    }

    private func hierarchyRow(_ parent: JellyfinItem) -> some View {
        NavigationLink {
            ItemDetailView(item: parent).id(parent.id)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(item: parent, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Found in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(parent.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func metadataItems(for target: JellyfinItem) -> [MetadataItem] {
        var metadata: [MetadataItem] = []

        if let criticRating = target.criticRating {
            metadata.append(.init(title: "Critic score", value: "\(criticRating)%", systemImage: "chair.lounge.fill", primaryColor: .red, secondaryColor: .orange))
        }
        if let communityRating = target.communityRating {
            metadata.append(.init(title: "Community rating", value: String(format: "%.1f / 10", communityRating), systemImage: "popcorn.fill", primaryColor: .yellow, secondaryColor: .red))
        }
        if let officialRating = target.officialRating, !officialRating.isEmpty {
            metadata.append(.init(title: "Classification", value: officialRating, systemImage: "checkmark.seal.fill", primaryColor: .white, secondaryColor: .green))
        }
        if let studio = target.studios?.first?.name, !studio.isEmpty {
            metadata.append(.init(title: "Studio", value: studio, systemImage: "building.2.fill", primaryColor: .blue, secondaryColor: .indigo))
        }
        return metadata
    }

    @ViewBuilder private func detailSubtitle(for target: JellyfinItem) -> some View {
        switch target.type {
        case "Episode":
            HStack {
                Text(episodeText(for: target))
                Spacer(minLength: 8)
                Text(mediaSizeText(for: target))
            }
            .foregroundStyle(.secondary)
        case "Season":
            let count = target.childCount ?? children.count
            Text("\(count) \(count == 1 ? "episode" : "episodes")")
                .foregroundStyle(.secondary)
        case "Series":
            Text(target.seasonCountText ?? "\(target.childCount ?? 0) seasons")
                .foregroundStyle(.secondary)
        case "Movie":
            Text(mediaSizeText(for: target))
                .foregroundStyle(.secondary)
        default:
            Text(target.detailLine)
                .foregroundStyle(.secondary)
        }
    }

    private func episodeText(for target: JellyfinItem) -> String {
        guard let season = target.parentIndexNumber, let episode = target.indexNumber else { return target.detailLine }
        return "Season \(season) · Episode \(episode)"
    }

    private func mediaSizeText(for target: JellyfinItem) -> String {
        let size = downloads.contentSizeBytes(itemID: target.id, account: session.account)
            ?? target.size
            ?? target.mediaSources?.first?.size
        guard let size else { return "Size unavailable" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    @ViewBuilder private var actionRow: some View {
        let target = details ?? item
        if target.type == "Movie" || target.type == "Episode" {
            let isLoading = player.loadingItemID == target.id
            HStack(spacing: 10) {
                Button { Task { await play(target) } } label: {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else if target.canResume, let progress = target.progressPercent {
                            WatchProgressIndicator(progress: progress, size: 20, tint: .white)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(target.canResume ? "Resume" : "Play")
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isLoading)

                downloadButton(for: target)
                audioTrackButton(for: target)
            }
        }
    }

    @ViewBuilder private func audioTrackButton(for target: JellyfinItem) -> some View {
        let tracks = audioTracks(for: target)
        if tracks.count > 1 {
            Menu {
                Picker("Audio Track", selection: $selectedAudioStreamIndex) {
                    ForEach(tracks) { track in
                        Text(track.audioTrackName).tag(Optional(track.index))
                    }
                }
            } label: {
                Image(systemName: "quote.bubble")
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Choose audio track")
        }
    }

    private func audioTracks(for target: JellyfinItem) -> [MediaStream] {
        target.mediaSources?.first?.mediaStreams?.filter { $0.type == "Audio" } ?? []
    }

    private func load() async {
        if let cached = itemDetailCache.entry(for: item.id, account: session.account) {
            details = cached.details
            children = cached.children
            hierarchyParent = cached.hierarchyParent
            serverReachable = cached.serverReachable
            error = nil
            return
        }

        details = nil
        children = []
        hierarchyParent = nil
        error = nil
        selectedAudioStreamIndex = nil
        guard let api = session.api else { return }
        let reachability = await api.reachability()
        if reachability == .unauthorized {
            session.handle(JellyfinError.unauthorized)
            return
        }
        serverReachable = reachability == .reachable
        guard serverReachable else {
            if downloads.localAssetURL(itemID: item.id, account: session.account) == nil {
                error = "Jellyfin is unavailable."
            }
            return
        }
        do {
            details = try await api.item(id: item.id)
            if item.type == "Series" {
                children = try await api.children(parentID: item.id, type: "Season")
            } else if item.type == "Season" {
                children = try await api.children(parentID: item.id, type: "Episode")
            }
            let current = details ?? item
            let parentID = current.type == "Episode" ? (current.seasonID ?? current.parentID) : current.parentID
            if (current.type == "Episode" || current.type == "Season"), let parentID {
                hierarchyParent = try await api.item(id: parentID)
            }
            itemDetailCache.store(
                .init(
                    details: details ?? item,
                    children: children,
                    hierarchyParent: hierarchyParent,
                    serverReachable: serverReachable
                ),
                for: item.id,
                account: session.account
            )
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }
    }

    private func favouriteSeason(for episode: JellyfinItem) async {
        guard let seasonID = episode.seasonID,
              let account = session.account,
              let api = session.api
        else { return }

        do {
            let season = try await api.item(id: seasonID)
            favourites.favourite(season, account: account)
            showFavouriteMessage(for: season, wasAdded: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func play(_ target: JellyfinItem) async {
        guard let account = session.account else { return }
        if downloads.localAssetURL(itemID: target.id, account: account) != nil {
            await playDownloaded(target)
            return
        }
        await playServer(target)
    }

    private func playServer(_ target: JellyfinItem) async {
        guard let api = session.api else {
            error = "Jellyfin is unavailable."
            return
        }
        do {
            try await player.play(item: target, api: api, audioStreamIndex: selectedAudioStreamIndex)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func playDownloaded(_ target: JellyfinItem) async {
        guard let account = session.account else { return }
        do { try await player.playDownloaded(item: target, account: account) }
        catch { self.error = error.localizedDescription }
    }

    private func downloadAction(_ target: JellyfinItem, audioStreamIndex: Int? = nil) {
        guard let account = session.account else { return }
        switch downloads.state(for: target.id, account: account) {
        case .notDownloaded, .failed:
            guard let api = session.api, serverReachable else {
                error = "Connect to Jellyfin to download this media."
                return
            }
            Task { await downloads.download(target, api: api, audioStreamIndex: audioStreamIndex) }
        case .downloading:
            downloads.cancel(itemID: target.id, account: account)
        case .downloaded:
            downloads.remove(itemID: target.id, account: account)
        }
    }

    @ViewBuilder private func downloadIcon(for target: JellyfinItem) -> some View {
        let state = downloads.state(for: target.id, account: session.account)
        switch state {
        case .notDownloaded, .failed:
            Image(systemName: "tray.and.arrow.down.fill")
        case let .downloading(progress):
            ZStack {
                Circle().stroke(.secondary.opacity(0.3), lineWidth: 3)
                Circle().trim(from: 0, to: progress).stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                Image(systemName: "xmark")
                    .font(Font.system(size: 8, weight: .bold))
            }
            .padding(11)
        case .downloaded:
            Image(systemName: "trash")
        }
    }

    @ViewBuilder private func downloadButton(for target: JellyfinItem) -> some View {
        let state = downloads.state(for: target.id, account: session.account)
        if case .downloaded = state {
            Button { downloadAction(target) } label: {
                Text("Remove Download")
                    .frame(height: 32)
            }
            .buttonStyle(.bordered)
        } else if shouldChooseAudioTrackBeforeDownloading(state: state, target: target) {
            Menu {
                Text("Audio Track")
                    .disabled(true)
                ForEach(audioTracks(for: target)) { track in
                    Button(track.audioTrackName) {
                        downloadAction(target, audioStreamIndex: track.index)
                    }
                }
            } label: {
                downloadIcon(for: target)
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel(downloadLabel(for: target))
        } else {
            Button { downloadAction(target) } label: {
                downloadIcon(for: target)
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(downloadLabel(for: target))
        }
    }

    private func shouldChooseAudioTrackBeforeDownloading(
        state: OfflineDownloadState,
        target: JellyfinItem
    ) -> Bool {
        switch state {
        case .notDownloaded, .failed:
            audioTracks(for: target).count > 1
        case .downloading, .downloaded:
            false
        }
    }

    private func downloadLabel(for target: JellyfinItem) -> String {
        switch downloads.state(for: target.id, account: session.account) {
        case .notDownloaded: "Download"
        case .downloading: "Cancel download"
        case .downloaded: "Remove download"
        case .failed: "Retry download"
        }
    }
}

private struct MetadataItem: Identifiable {
    let title: String
    let value: String
    let systemImage: String
    let primaryColor: Color
    let secondaryColor: Color

    var id: String { title }
}
