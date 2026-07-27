import SwiftUI

struct CatalogView: View {
    @ObservedObject var session: JellyfinSession
    let type: String
    let title: String
    @State private var items: [JellyfinItem] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { ItemRow(item: $0) }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
                .overlay { if items.isEmpty && error == nil { ProgressView() } }
                .navigationTitle(title)
                .task { await load() }
        }
    }

    private func load() async {
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
