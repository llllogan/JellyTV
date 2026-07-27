import SwiftUI

struct SearchLibraryView: View {
    @ObservedObject var session: JellyfinSession
    @State private var query = ""
    @State private var items: [JellyfinItem] = []
    @State private var error: String?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    ContentUnavailableView(
                        "Search your library",
                        systemImage: "magnifyingglass",
                        description: Text("Find movies and TV shows.")
                    )
                } else {
                    ForEach(items) { ItemRow(item: $0) }
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .searchable(text: $query, prompt: "Movies and TV shows")
            .searchFocused($isSearchFocused)
            .onSubmit(of: .search) { Task { await search() } }
            .onAppear { isSearchFocused = true }
            .navigationTitle("Search")
        }
    }

    private func search() async {
        guard let api = session.api, !query.isEmpty else {
            items = []
            return
        }
        do {
            items = try await api.items(type: "Movie,Series", search: query)
            error = nil
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }
    }
}
