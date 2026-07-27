import SwiftUI

struct SeerrGenreBrowseSection: View {
    enum MediaType {
        case movie
        case tv

        var label: String { self == .movie ? "Movies" : "TV" }
    }

    let genre: SeerrGenre
    let mediaType: MediaType
    @ObservedObject var session: SeerrSession
    let items: [SeerrMedia]

    var body: some View {
        if !items.isEmpty {
            Section("\(genre.name) \(mediaType.label)") {
                SeerrMediaCarousel(items: items, session: session)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }
}
