import SwiftUI

#Preview("Action row buttons") {
    VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
        Button {
        } label: {
            Label("Play", systemImage: "play.fill")
                .padding(.horizontal, 14)
                .frame(height: 32)
        }
        .buttonStyle(.borderedProminent)

        Button {
        } label: {
            HStack(spacing: 8) {
                WatchProgressIndicator(progress: 0.55, size: 22, tint: .white)
                Text("Resume")
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
        }
        .buttonStyle(.borderedProminent)

        Menu {
            Picker("Audio Track", selection: .constant(0)) {
                Text("English").tag(0)
                Text("Japanese").tag(1)
            }
        } label: {
            Image(systemName: "quote.bubble")
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
        }
        .accessibilityLabel("Choose audio track")
        }

        HStack(spacing: 10) {
        Menu {
            Text("Choose audio track to download")
                .disabled(true)
            Button("English") {}
            Button("Japanese") {}
        } label: {
            Image(systemName: "tray.and.arrow.down")
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
        }
        .accessibilityLabel("Download")

        Button {
        } label: {
            Image(systemName: "xmark")
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel download")

        Button("Remove Download") {
        }
        .buttonStyle(.bordered)
        }
    }
    .padding()
}
