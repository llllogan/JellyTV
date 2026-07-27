import SwiftUI

struct MediaCard: View {
    let item: JellyfinItem
    let detailStyle: MediaCarousel.DetailStyle
    let cardWidth: CGFloat?

    init(item: JellyfinItem, detailStyle: MediaCarousel.DetailStyle, cardWidth: CGFloat? = nil) {
        self.item = item
        self.detailStyle = detailStyle
        self.cardWidth = cardWidth
    }

    private var resolvedCardWidth: CGFloat { cardWidth ?? 148 }
    private var artworkWidth: CGFloat { resolvedCardWidth - 16 }
    private var artworkHeight: CGFloat { artworkWidth * 1.5 }

    private var detailText: String {
        switch detailStyle {
        case .runtime:
            item.seasonCountText ?? item.runtimeText ?? "Runtime unavailable"
        case .remainingTime:
            item.type == "Episode"
                ? item.detailLine
                : item.remainingTimeText ?? "Remaining time unavailable"
        case .nextUp:
            "\(item.detailLine)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(item: item, width: artworkWidth, height: artworkHeight)
            HStack(spacing: 8) {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if case .nextUp = detailStyle {
                    Text(item.runtimeText ?? "Runtime unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if case .remainingTime = detailStyle,
                   let progress = item.progressPercent
                {
                    WatchProgressIndicator(progress: progress)
                }
            }
        }
        .padding(8)
        .frame(width: resolvedCardWidth)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct WatchProgressIndicator: View {
    let progress: Double
    var size: CGFloat = 14
    var tint: Color = .purple

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: 2)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(Int(clampedProgress * 100)) percent watched")
    }
}
