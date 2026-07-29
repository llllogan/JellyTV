import SwiftUI

struct SearchLibraryView: View {
    @ObservedObject var session: JellyfinSession
    @ObservedObject var seerrSession: SeerrSession
    @State private var query = ""
    @State private var items: [JellyfinItem] = []
    @State private var seerrItems: [SeerrMedia] = []
    @State private var error: String?
    @State private var showServers = false
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
                    .listRowInsets(EdgeInsets())
                    .background(Color(uiColor: .systemBackground))
                } else {
                    if !items.isEmpty {
                        Section("In Your Library") {
                            ForEach(items) { ItemRow(item: $0) }
                        }
                        .listRowBackground(Color(uiColor: .secondarySystemBackground))
                    }
                    if !seerrItems.isEmpty {
                        Section("Avaiable to request") {
                            ForEach(seerrItems) { SeerrSearchRow(media: $0, session: seerrSession) }
                        }
                        .listRowBackground(Color(uiColor: .secondarySystemBackground))
                    }
                    if items.isEmpty && seerrItems.isEmpty && error == nil {
                        ContentUnavailableView("No results", systemImage: "magnifyingglass")
                            .listRowInsets(EdgeInsets())
                            .background(Color(uiColor: .systemBackground))
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemBackground))
            .searchable(text: $query, prompt: "Movies and TV shows")
            .searchFocused($isSearchFocused)
            .onAppear { isSearchFocused = true }
            .navigationTitle("Search")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showServers = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showServers) {
                ServersView(jellyfinSession: session, seerrSession: seerrSession)
            }
            .task(id: query) {
                let searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !searchQuery.isEmpty else {
                    items = []
                    seerrItems = []
                    error = nil
                    return
                }

                do {
                    try await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    await search(for: searchQuery)
                } catch is CancellationError {
                    // A newer keystroke replaced this pending search.
                } catch {
                    // Task.sleep only throws cancellation errors.
                }
            }
        }
    }

    private func search(for searchQuery: String) async {
        guard let api = session.api else {
            items = []
            seerrItems = []
            return
        }
        async let jellyfinSearch = api.items(type: "Movie,Series", search: searchQuery)
        do {
            let results = try await jellyfinSearch
            guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines) == searchQuery else { return }
            items = results
            error = nil
        } catch {
            guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines) == searchQuery else { return }
            session.handle(error)
            self.error = error.localizedDescription
        }
        if let seerrAPI = seerrSession.api {
            do {
                let results = try await seerrAPI.search(query: searchQuery)
                guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines) == searchQuery else { return }
                seerrItems = results
            } catch {
                guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines) == searchQuery else { return }
                seerrSession.handle(error)
            }
        } else {
            seerrItems = []
        }
    }
}
