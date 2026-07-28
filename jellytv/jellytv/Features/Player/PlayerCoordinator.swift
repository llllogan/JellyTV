import AVKit
import AVFAudio
import Combine
import MediaPlayer
import UIKit

@MainActor
final class PlayerCoordinator: NSObject, ObservableObject {
    @Published var controller: AVPlayerViewController?
    @Published var isPresenting = false

    private var player: AVPlayer?
    private var timer: Any?
    private var item: JellyfinItem?
    private var api: JellyfinAPI?
    private var sessionID: String?
    private var offlineAccount: Account?
    private var artworkTask: Task<Void, Never>?
    private var remoteCommandsConfigured = false
    private var timeControlObservation: NSKeyValueObservation?
    private var playbackEndedObserver: NSObjectProtocol?

    func play(item: JellyfinItem, api: JellyfinAPI, audioStreamIndex: Int? = nil) async throws {
        stop()
        try configureAudioSession()

        let resumeTicks = item.userData?.playbackPositionTicks ?? 0
        let info = try await api.playbackInfo(itemID: item.id, positionTicks: resumeTicks, audioStreamIndex: audioStreamIndex)
        guard let source = info.mediaSources.first else {
            throw JellyfinError.requestFailed("No playable media source was returned.")
        }

        self.item = item
        self.api = api
        sessionID = info.playSessionID

        let asset = AVURLAsset(
            url: api.playbackURL(itemID: item.id, source: source, audioStreamIndex: audioStreamIndex),
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": [
                    "Authorization": "MediaBrowser Token=\"\(api.account.token)\"",
                ],
            ]
        )
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        self.player = player
        configurePlayerObservations(player)

        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
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
        configureRemoteCommands()
        publishNowPlayingInfo(for: item, player: player)
        player.play()
        updateNowPlayingPlaybackState()
    }

    func playDownloaded(item: JellyfinItem, account: Account) throws {
        guard let url = OfflineDownloadManager.shared.localAssetURL(itemID: item.id, account: account) else {
            throw JellyfinError.requestFailed("The downloaded media is no longer available.")
        }
        stop()
        try configureAudioSession()
        self.item = item
        offlineAccount = account
        api = nil
        sessionID = nil
        let player = AVPlayer(playerItem: AVPlayerItem(url: url))
        self.player = player
        configurePlayerObservations(player)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.controller = controller
        isPresenting = true
        let resumeTicks = OfflineDownloadManager.shared.playbackPosition(itemID: item.id, account: account)
        if resumeTicks > 0 { player.seek(to: CMTime(value: resumeTicks, timescale: 10_000_000)) }
        timer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 15, preferredTimescale: 1), queue: .main) { [weak self] time in
            Task { await self?.progress(time) }
        }
        configureRemoteCommands()
        publishNowPlayingInfo(for: item, player: player)
        player.play()
        updateNowPlayingPlaybackState()
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
        if let item, let offlineAccount {
            OfflineDownloadManager.shared.queueProgressSync(
                itemID: item.id,
                account: offlineAccount,
                ticks: Int64((player?.currentTime().seconds ?? 0) * 10_000_000)
            )
        }
        if let timer {
            player?.removeTimeObserver(timer)
        }

        timer = nil
        timeControlObservation = nil
        if let playbackEndedObserver {
            NotificationCenter.default.removeObserver(playbackEndedObserver)
            self.playbackEndedObserver = nil
        }
        artworkTask?.cancel()
        artworkTask = nil
        player?.pause()
        player = nil
        offlineAccount = nil
        controller = nil
        isPresenting = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func progress(_ time: CMTime) async {
        guard let item else { return }
        let ticks = Int64(time.seconds * 10_000_000)
        if let api {
            await api.report("Sessions/Playing/Progress", itemID: item.id, positionTicks: ticks, playSessionID: sessionID)
        } else if let offlineAccount {
            OfflineDownloadManager.shared.updatePlayback(itemID: item.id, account: offlineAccount, ticks: ticks)
        }
        updateNowPlayingPlaybackState(elapsedTime: time.seconds)
    }

    private func configureRemoteCommands() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.player?.play()
            self?.updateNowPlayingPlaybackState()
            return self?.player == nil ? .noSuchContent : .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause()
            self?.updateNowPlayingPlaybackState()
            return self?.player == nil ? .noSuchContent : .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, let player = self.player else { return .noSuchContent }
            if player.timeControlStatus == .playing { player.pause() } else { player.play() }
            self.updateNowPlayingPlaybackState()
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent, let player = self.player else {
                return .noSuchContent
            }
            player.seek(to: CMTime(seconds: event.positionTime, preferredTimescale: 1_000))
            self.updateNowPlayingPlaybackState(elapsedTime: event.positionTime)
            return .success
        }
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in self?.skip(by: 15) ?? .noSuchContent }
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in self?.skip(by: -15) ?? .noSuchContent }
    }

    private func configurePlayerObservations(_ player: AVPlayer) {
        timeControlObservation = player.observe(\AVPlayer.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateNowPlayingPlaybackState() }
        }
        if let playbackEndedObserver {
            NotificationCenter.default.removeObserver(playbackEndedObserver)
        }
        playbackEndedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    private func skip(by seconds: Double) -> MPRemoteCommandHandlerStatus {
        guard let player else { return .noSuchContent }
        let target = max(0, player.currentTime().seconds + seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 1_000))
        updateNowPlayingPlaybackState(elapsedTime: target)
        return .success
    }

    private func publishNowPlayingInfo(for item: JellyfinItem, player: AVPlayer) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.name,
            MPMediaItemPropertyMediaType: MPMediaType.movie.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]

        if item.type == "Episode" {
            info[MPMediaItemPropertyAlbumTitle] = item.seriesName ?? "Episode"
            let seasonEpisode = [
                item.parentIndexNumber.map { "Season \($0)" },
                item.indexNumber.map { "Episode \($0)" },
            ].compactMap { $0 }.joined(separator: " · ")
            if !seasonEpisode.isEmpty { info[MPMediaItemPropertyArtist] = seasonEpisode }
        }
        if let runTimeTicks = item.runTimeTicks {
            info[MPMediaItemPropertyPlaybackDuration] = Double(runTimeTicks) / 10_000_000
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        guard let artworkURL = item.imageURL else { return }
        artworkTask?.cancel()
        artworkTask = Task { [artworkURL] in
            do {
                let (data, _) = try await URLSession.shared.data(from: artworkURL)
                guard !Task.isCancelled, let image = UIImage(data: data) else { return }
                var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
                updatedInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
            } catch {
                // Artwork is optional; playback metadata remains available without it.
            }
        }
    }

    private func updateNowPlayingPlaybackState(elapsedTime: Double? = nil) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo, let player else { return }
        let currentTime = elapsedTime ?? player.currentTime().seconds
        if currentTime.isFinite { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime }
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.timeControlStatus == .playing ? player.rate : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
