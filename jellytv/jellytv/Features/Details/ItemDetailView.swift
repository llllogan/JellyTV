import SwiftUI

struct ItemDetailView: View {
    let item: JellyfinItem
    @EnvironmentObject private var player: PlayerCoordinator
    @EnvironmentObject private var session: JellyfinSession
    @State private var details: JellyfinItem?
    @State private var children: [JellyfinItem] = []
    @State private var hierarchyParent: JellyfinItem?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    ArtworkView(item: item, width: 180, height: 270)
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 2) {
                        Text((details ?? item).name).font(.title.bold())
                        if let episodeMetadata {
                            Text(episodeMetadata).foregroundStyle(.secondary)
                        }
                    }
                    actionRow
                    if let overview = (details ?? item).overview { Text(overview).foregroundStyle(.secondary) }
                    ForEach(children) { child in ItemRow(item: child) }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                .padding(.bottom)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)

            if let hierarchyParent {
                Section {
                    hierarchyRow(hierarchyParent)
                }
                .listRowBackground(Color(uiColor: .systemGroupedBackground))
            }
        }
        .listStyle(.insetGrouped)
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

    private var episodeMetadata: String? {
        let target = details ?? item
        guard target.type == "Episode",
              let episode = target.indexNumber,
              let season = target.parentIndexNumber
        else { return nil }
        return "e\(episode) s\(season)"
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

                Button { } label: {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Download")

                if target.canDelete == true {
                    Button { } label: {
                        Image(systemName: "trash")
                            .frame(width: 44, height: 44)
                            .background(.thinMaterial, in: Circle())
                    }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete")
                }
            }
        }
    }

    private func load() async {
        guard let api = session.api else { return }
        details = nil
        children = []
        hierarchyParent = nil
        error = nil
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
        guard let api = session.api else { return }
        do {
            try await player.play(item: target, api: api)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
