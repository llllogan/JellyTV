import SwiftUI

struct ItemDetailView: View {
    let item: JellyfinItem
    @EnvironmentObject private var player: PlayerCoordinator
    @EnvironmentObject private var session: JellyfinSession
    @EnvironmentObject private var downloads: OfflineDownloadManager
    @State private var details: JellyfinItem?
    @State private var children: [JellyfinItem] = []
    @State private var hierarchyParent: JellyfinItem?
    @State private var error: String?
    @State private var serverReachable = false
    @State private var scrollPosition: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    ArtworkView(item: item, width: 180, height: 270)
                        .frame(maxWidth: .infinity)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text((details ?? item).name).font(.title.bold())
                        detailSubtitle(for: details ?? item)
                    }
                    
                    actionRow
                    
                    let target = details ?? item
                    if case let .downloading(progress) = downloads.state(for: target.id, account: session.account) {
                        Text("Downloading \(Int(progress * 100))% (\(ByteCountFormatter.string(fromByteCount: downloads.downloadedBytes(itemID: target.id, account: session.account), countStyle: .file)))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if case let .failed(message) = downloads.state(for: (details ?? item).id, account: session.account) {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                    if let overview = (details ?? item).overview { Text(overview).foregroundStyle(.secondary) }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                .padding(.bottom)
                .id("summary")
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)

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

            if let hierarchyParent {
                Section {
                    hierarchyRow(hierarchyParent)
                }
                .listRowBackground(Color(uiColor: .systemGroupedBackground))
            }
        }
        .listStyle(.insetGrouped)
        .scrollPosition(id: $scrollPosition)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(item.type == "Series" ? "Show" : "Details")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.id) { await load() }
    }

    private func hierarchyRow(_ parent: JellyfinItem) -> some View {
        NavigationLink {
            ItemDetailView(item: parent).id(parent.id)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(item: parent, width: 58, height: 82)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Found in").font(.caption).foregroundStyle(.secondary)
                    Text(parent.name).font(.headline)
                }
            }
        }
        .buttonStyle(.plain)
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
            HStack(spacing: 10) {
                Button { Task { await play(target) } } label: {
                    HStack(spacing: 8) {
                        if target.canResume, let progress = target.progressPercent {
                            WatchProgressIndicator(progress: progress, size: 22, tint: .white)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(target.canResume ? "Resume" : "Play")
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                downloadButton(for: target)
            }
        }
    }

    private func load() async {
        details = nil
        children = []
        hierarchyParent = nil
        error = nil
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
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }
    }

    private func play(_ target: JellyfinItem) async {
        guard let account = session.account else { return }
        if downloads.localAssetURL(itemID: target.id, account: account) != nil {
            playDownloaded(target)
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
            try await player.play(item: target, api: api)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func playDownloaded(_ target: JellyfinItem) {
        guard let account = session.account else { return }
        do { try player.playDownloaded(item: target, account: account) }
        catch { self.error = error.localizedDescription }
    }

    private func downloadAction(_ target: JellyfinItem) {
        guard let account = session.account else { return }
        switch downloads.state(for: target.id, account: account) {
        case .notDownloaded, .failed:
            guard let api = session.api, serverReachable else {
                error = "Connect to Jellyfin to download this media."
                return
            }
            Task { await downloads.download(target, api: api) }
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
            Image(systemName: "tray.and.arrow.down")
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
        if case .downloaded = downloads.state(for: target.id, account: session.account) {
            Button { downloadAction(target) } label: {
                Text("Remove Download")
                    .frame(height: 32)
            }
                .buttonStyle(.bordered)
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

    private func downloadLabel(for target: JellyfinItem) -> String {
        switch downloads.state(for: target.id, account: session.account) {
        case .notDownloaded: "Download"
        case .downloading: "Cancel download"
        case .downloaded: "Remove download"
        case .failed: "Retry download"
        }
    }
}
