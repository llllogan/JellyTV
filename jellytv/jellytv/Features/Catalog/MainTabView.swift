import SwiftUI

struct MainTabView: View {
    @ObservedObject var session: JellyfinSession
    @ObservedObject var seerrSession: SeerrSession

    var body: some View {
        TabView {
            Tab("Browse", systemImage: "rectangle.grid.2x2") {
                BrowseView(session: session, seerrSession: seerrSession)
            }
            Tab("Movies", systemImage: "film") {
                CatalogView(session: session, type: "Movie", title: "Movies")
            }
            Tab("TV", systemImage: "tv") {
                CatalogView(session: session, type: "Series", title: "TV Shows")
            }
            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                SearchLibraryView(session: session, seerrSession: seerrSession)
            }
        }
    }
}
