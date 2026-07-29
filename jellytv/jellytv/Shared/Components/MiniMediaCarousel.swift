import SwiftUI

struct MiniMediaCarousel: View {
    let items: [JellyfinItem]

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(items) { item in
                    NavigationLink {
                        ItemDetailView(item: item)
                            .id(item.id)
                    } label: {
                        MiniMediaCard(item: item)
                    }
                    .buttonStyle(.plain)
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

private struct MiniMediaCard: View {
    let item: JellyfinItem

    private var subtitle: String {
        if item.type == "Movie" {
            return item.runtimeText ?? "Runtime unavailable"
        }
        if let season = item.parentIndexNumber, let episode = item.indexNumber {
            return "Season \(season) · Episode \(episode)"
        }
        return item.detailLine
    }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(item: item, width: 44, height: 66)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(width: 270, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
