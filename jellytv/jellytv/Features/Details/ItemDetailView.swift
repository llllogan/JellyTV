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
                if let overview = (details ?? item).overview {
                    Text(overview).foregroundStyle(.secondary)
                }
                if item.type == "Movie" || item.type == "Episode" {
                    playButton
                }
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

    private var playButton: some View {
        Button {
            Task { await play(details ?? item) }
        } label: {
            Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
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
