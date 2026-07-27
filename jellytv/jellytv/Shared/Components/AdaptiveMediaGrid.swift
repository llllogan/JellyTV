import SwiftUI

struct AdaptiveMediaGrid: View {
    let items: [JellyfinItem]
    let detailStyle: (JellyfinItem) -> MediaCarousel.DetailStyle
    let onSelect: (JellyfinItem) -> Void

    private let columns = [GridItem(.adaptive(minimum: 145, maximum: 200), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items) { item in
                GeometryReader { proxy in
                    Button {
                        onSelect(item)
                    } label: {
                        MediaCard(item: item, detailStyle: detailStyle(item), cardWidth: proxy.size.width)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
                .aspectRatio(148 / 237, contentMode: .fit)
            }
        }
    }
}
