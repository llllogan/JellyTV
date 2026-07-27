import SwiftUI

struct ItemRow: View {
    let item: JellyfinItem

    var body: some View {
        NavigationLink {
            ItemDetailView(item: item)
                .id(item.id)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(item: item, width: 70, height: 100)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name)
                        .font(.headline)
                    Text(item.detailLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let percent = item.progressPercent {
                        ProgressView(value: percent).tint(.accentColor)
                    }
                }
            }
            .padding(.vertical, 3)
        }
    }
}
