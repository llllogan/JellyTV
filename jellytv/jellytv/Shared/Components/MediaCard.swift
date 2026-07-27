import SwiftUI

struct MediaCard: View {
    let item: JellyfinItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(item: item, width: 132, height: 198)
            Text(item.runtimeText ?? "Runtime unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(width: 148)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
