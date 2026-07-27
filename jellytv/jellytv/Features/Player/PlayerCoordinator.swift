import AVKit
import AVFAudio
import Combine

@MainActor
final class PlayerCoordinator: NSObject, ObservableObject {
    @Published var controller: AVPlayerViewController?
    @Published var isPresenting = false

    private var player: AVPlayer?
    private var timer: Any?
    private var item: JellyfinItem?
    private var api: JellyfinAPI?
    private var sessionID: String?

    func play(item: JellyfinItem, api: JellyfinAPI) async throws {
        stop()
        try configureAudioSession()

        let resumeTicks = item.userData?.playbackPositionTicks ?? 0
        let info = try await api.playbackInfo(itemID: item.id, positionTicks: resumeTicks)
        guard let source = info.mediaSources.first else {
            throw JellyfinError.requestFailed("No playable media source was returned.")
        }

        self.item = item
        self.api = api
        sessionID = info.playSessionID

        let asset = AVURLAsset(
            url: api.playbackURL(itemID: item.id, source: source),
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": [
                    "Authorization": "MediaBrowser Token=\"\(api.account.token)\"",
                ],
            ]
        )
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        self.player = player

        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        self.controller = controller
        isPresenting = true

        if resumeTicks > 0 {
            await player.seek(to: CMTime(value: resumeTicks, timescale: 10_000_000))
        }
        await api.report(
            "Sessions/Playing",
            itemID: item.id,
            positionTicks: resumeTicks,
            playSessionID: sessionID
        )

        timer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 15, preferredTimescale: 1),
            queue: .main
        ) { [weak self] time in
            Task { await self?.progress(time) }
        }
        player.play()
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
        try audioSession.setActive(true)
    }

    func stop() {
        if let item, let api {
            Task {
                await api.report(
                    "Sessions/Playing/Stopped",
                    itemID: item.id,
                    positionTicks: Int64((player?.currentTime().seconds ?? 0) * 10_000_000),
                    playSessionID: sessionID
                )
            }
        }
        if let timer {
            player?.removeTimeObserver(timer)
        }

        timer = nil
        player?.pause()
        player = nil
        controller = nil
        isPresenting = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func progress(_ time: CMTime) async {
        guard let item, let api else { return }
        await api.report(
            "Sessions/Playing/Progress",
            itemID: item.id,
            positionTicks: Int64(time.seconds * 10_000_000),
            playSessionID: sessionID
        )
    }
}
