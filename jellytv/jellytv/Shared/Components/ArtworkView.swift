import SwiftUI

struct ArtworkView: View {
    let item: JellyfinItem
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        AsyncImage(url: item.imageURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.gray.opacity(0.18)
                .overlay(Image(systemName: "film"))
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
