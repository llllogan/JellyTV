import SwiftUI

struct ArtworkView: View {
    let item: JellyfinItem
    let width: CGFloat?
    let height: CGFloat
    @EnvironmentObject private var downloads: OfflineDownloadManager
    @EnvironmentObject private var session: JellyfinSession

    init(item: JellyfinItem, width: CGFloat? = nil, height: CGFloat) {
        self.item = item
        self.width = width
        self.height = height
    }

    var body: some View {
        AsyncImage(url: downloads.localArtworkURL(itemID: item.id, account: session.account) ?? item.imageURL) { image in
            if let width {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
            } else {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(height: height)
            }
        } placeholder: {
            Color.gray.opacity(0.18)
                .overlay(Image(systemName: "film"))
                .frame(width: width ?? height * 2 / 3, height: height)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
