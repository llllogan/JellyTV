import SwiftUI

struct ArtworkView: View {
    let item: JellyfinItem
    let width: CGFloat?
    let height: CGFloat?
    let preferredArtworkURL: URL?
    let fillsFrame: Bool
    let cornerRadius: CGFloat
    @EnvironmentObject private var downloads: OfflineDownloadManager
    @EnvironmentObject private var session: JellyfinSession

    init(
        item: JellyfinItem,
        width: CGFloat? = nil,
        height: CGFloat?,
        preferredArtworkURL: URL? = nil,
        fillsFrame: Bool = false,
        cornerRadius: CGFloat = 8
    ) {
        self.item = item
        self.width = width
        self.height = height
        self.preferredArtworkURL = preferredArtworkURL
        self.fillsFrame = fillsFrame
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        AsyncImage(url: preferredArtworkURL ?? fallbackArtworkURL) { phase in
            switch phase {
            case let .success(image):
                artworkImage(image)
            case .failure:
                if preferredArtworkURL != nil {
                    fallbackArtwork
                } else {
                    placeholder
                }
            case .empty:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var fallbackArtworkURL: URL? {
        downloads.localArtworkURL(itemID: item.id, account: session.account) ?? item.imageURL
    }

    @ViewBuilder private var fallbackArtwork: some View {
        if let fallbackArtworkURL {
            AsyncImage(url: fallbackArtworkURL) { phase in
                if case let .success(image) = phase {
                    artworkImage(image)
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    @ViewBuilder private func artworkImage(_ image: Image) -> some View {
        if fillsFrame, let height {
            image
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: height)
        } else if fillsFrame {
            image
                .resizable()
                .scaledToFit()
                .containerRelativeFrame(.horizontal)
        } else if let width, let height {
            image
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
        } else if let height {
            image
                .resizable()
                .scaledToFit()
                .frame(height: height)
        } else {
            image
                .resizable()
                .scaledToFit()
        }
    }

    @ViewBuilder private var placeholder: some View {
        if fillsFrame, height == nil {
            Color.gray.opacity(0.18)
                .overlay(Image(systemName: "film"))
                .frame(maxWidth: .infinity)
                .aspectRatio(2 / 3, contentMode: .fit)
        } else {
        Color.gray.opacity(0.18)
            .overlay(Image(systemName: "film"))
            .frame(
                maxWidth: fillsFrame ? .infinity : nil,
                minHeight: height,
                maxHeight: height
            )
            .frame(width: fillsFrame ? nil : width ?? (height ?? 0) * 2 / 3)
        }
    }
}
