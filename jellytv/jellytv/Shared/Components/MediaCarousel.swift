import SwiftUI

struct MediaCarousel: View {
    enum DetailStyle {
        case runtime
        case remainingTime
        case nextUp
    }

    let items: [JellyfinItem]
    let detailStyle: DetailStyle

    init(items: [JellyfinItem], detailStyle: DetailStyle = .runtime) {
        self.items = items
        self.detailStyle = detailStyle
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(items) { item in
                    NavigationLink {
                        ItemDetailView(item: item)
                            .id(item.id)
                    } label: {
                        MediaCard(item: item, detailStyle: detailStyle)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }
}
