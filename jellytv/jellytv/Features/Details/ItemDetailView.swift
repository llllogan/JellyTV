import SwiftUI

struct ItemDetailView: View {
    let item: JellyfinItem
    @EnvironmentObject private var player: PlayerCoordinator
    @EnvironmentObject private var session: JellyfinSession
    @State private var details: JellyfinItem?
    @State private var children: [JellyfinItem] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ArtworkView(item: item, width: 180, height: 270)
                    .frame(maxWidth: .infinity)
                Text((details ?? item).name).font(.title.bold())
                actionRow
                if let overview = (details ?? item).overview { Text(overview).foregroundStyle(.secondary) }
                ForEach(children) { child in ItemRow(item: child) }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle(item.type == "Series" ? "Show" : "Details")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.id) { await load() }
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
                    Image(systemName: "arrow.down")
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
        error = nil
        do {
            details = try await api.item(id: item.id)
            if item.type == "Series" {
                children = try await api.children(parentID: item.id, type: "Season")
            } else if item.type == "Season" {
                children = try await api.children(parentID: item.id, type: "Episode")
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
