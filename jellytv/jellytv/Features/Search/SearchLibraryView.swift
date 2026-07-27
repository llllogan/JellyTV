import SwiftUI

struct SearchLibraryView: View {
    @ObservedObject var session: JellyfinSession
    @ObservedObject var seerrSession: SeerrSession
    @State private var query = ""
    @State private var items: [JellyfinItem] = []
    @State private var seerrItems: [SeerrMedia] = []
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
                    if !items.isEmpty {
                        Section("In Your Library") {
                            ForEach(items) { ItemRow(item: $0) }
                        }
                    }
                    if !seerrItems.isEmpty {
                        Section("Avaiable to request") {
                            ForEach(seerrItems) { SeerrSearchRow(media: $0, session: seerrSession) }
                        }
                    }
                    if items.isEmpty && seerrItems.isEmpty && error == nil {
                        ContentUnavailableView("No results", systemImage: "magnifyingglass")
                    }
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
            .toolbarTitleDisplayMode(.inlineLarge)
        }
    }

    private func search() async {
        guard let api = session.api, !query.isEmpty else {
            items = []
            seerrItems = []
            return
        }
        async let jellyfinSearch = api.items(type: "Movie,Series", search: query)
        do {
            items = try await jellyfinSearch
            error = nil
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }
        if let seerrAPI = seerrSession.api {
            do { seerrItems = try await seerrAPI.search(query: query) }
            catch { seerrSession.handle(error) }
        } else {
            seerrItems = []
        }
    }
}
