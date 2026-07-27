import SwiftUI

struct ArtworkView: View {
    let item: JellyfinItem
    let width: CGFloat
    let height: CGFloat
    @EnvironmentObject private var downloads: OfflineDownloadManager
    @EnvironmentObject private var session: JellyfinSession

    var body: some View {
        AsyncImage(url: downloads.localArtworkURL(itemID: item.id, account: session.account) ?? item.imageURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.gray.opacity(0.18)
                .overlay(Image(systemName: "film"))
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
