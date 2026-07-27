import SwiftUI
import AVKit

struct NativePlayerView: View {
    @ObservedObject var coordinator: PlayerCoordinator

    var body: some View {
        PlayerControllerRepresentable(controller: coordinator.controller)
            .ignoresSafeArea()
            .onDisappear {
                coordinator.stop()
            }
    }
}

private struct PlayerControllerRepresentable: UIViewControllerRepresentable {
    let controller: AVPlayerViewController?
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        controller ?? AVPlayerViewController()
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
