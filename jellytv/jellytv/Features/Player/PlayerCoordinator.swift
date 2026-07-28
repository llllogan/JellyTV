import AVKit
import AVFAudio
import Combine
import MediaPlayer
import UIKit

@MainActor
final class PlayerCoordinator: NSObject, ObservableObject {
    @Published var controller: AVPlayerViewController?
    @Published var isPresenting = false
    @Published private(set) var loadingItemID: String?

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
    private var readinessObservation: NSKeyValueObservation?
    private var readinessContinuation: CheckedContinuation<Void, Error>?
    private var playbackRequestID: UUID?
    private var hasStartedPlayback = false

    func play(item: JellyfinItem, api: JellyfinAPI, audioStreamIndex: Int? = nil) async throws {
        guard loadingItemID != item.id else { return }
        stop()
        let requestID = beginLoading(itemID: item.id)

        do {
            try configureAudioSession()

            let resumeTicks = item.userData?.playbackPositionTicks ?? 0
            let info = try await api.playbackInfo(itemID: item.id, positionTicks: resumeTicks, audioStreamIndex: audioStreamIndex)
            guard isCurrent(requestID) else { return }
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
            let playerItem = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: playerItem)
            self.player = player
            try await waitUntilReady(playerItem)
            guard isCurrent(requestID) else { return }

            configurePlayerObservations(player)
            present(player)
            finishLoading(requestID)

            if resumeTicks > 0 {
                await player.seek(to: CMTime(value: resumeTicks, timescale: 10_000_000))
            }
            hasStartedPlayback = true
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
        } catch {
            guard isCurrent(requestID) else { return }
            stop()
            throw error
        }
    }

    func playDownloaded(item: JellyfinItem, account: Account) async throws {
        guard let url = OfflineDownloadManager.shared.localAssetURL(itemID: item.id, account: account) else {
            throw JellyfinError.requestFailed("The downloaded media is no longer available.")
        }
        guard loadingItemID != item.id else { return }
        stop()
        let requestID = beginLoading(itemID: item.id)

        do {
            try configureAudioSession()
            self.item = item
            offlineAccount = account
            api = nil
            sessionID = nil
            let playerItem = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: playerItem)
            self.player = player
            try await waitUntilReady(playerItem)
            guard isCurrent(requestID) else { return }

            configurePlayerObservations(player)
            present(player)
            finishLoading(requestID)

            let resumeTicks = OfflineDownloadManager.shared.playbackPosition(itemID: item.id, account: account)
            if resumeTicks > 0 { await player.seek(to: CMTime(value: resumeTicks, timescale: 10_000_000)) }
            hasStartedPlayback = true
            timer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 15, preferredTimescale: 1), queue: .main) { [weak self] time in
                Task { await self?.progress(time) }
            }
            configureRemoteCommands()
            publishNowPlayingInfo(for: item, player: player)
            player.play()
            updateNowPlayingPlaybackState()
        } catch {
            guard isCurrent(requestID) else { return }
            stop()
            throw error
        }
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
        try audioSession.setActive(true)
    }

    func stop() {
        if hasStartedPlayback, let item, let api {
            Task {
                await api.report(
                    "Sessions/Playing/Stopped",
                    itemID: item.id,
                    positionTicks: Int64((player?.currentTime().seconds ?? 0) * 10_000_000),
                    playSessionID: sessionID
                )
            }
        }
        if hasStartedPlayback, let item, let offlineAccount {
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
        cancelReadinessWait()
        timeControlObservation = nil
        if let playbackEndedObserver {
            NotificationCenter.default.removeObserver(playbackEndedObserver)
            self.playbackEndedObserver = nil
        }
        artworkTask?.cancel()
        artworkTask = nil
        player?.pause()
        player = nil
        item = nil
        api = nil
        sessionID = nil
        offlineAccount = nil
        controller = nil
        isPresenting = false
        loadingItemID = nil
        playbackRequestID = nil
        hasStartedPlayback = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginLoading(itemID: String) -> UUID {
        let requestID = UUID()
        playbackRequestID = requestID
        loadingItemID = itemID
        return requestID
    }

    private func isCurrent(_ requestID: UUID) -> Bool {
        playbackRequestID == requestID
    }

    private func finishLoading(_ requestID: UUID) {
        guard isCurrent(requestID) else { return }
        loadingItemID = nil
    }

    private func present(_ player: AVPlayer) {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.controller = controller
        isPresenting = true
    }

    private func waitUntilReady(_ playerItem: AVPlayerItem) async throws {
        switch playerItem.status {
        case .readyToPlay:
            return
        case .failed:
            throw readinessError(for: playerItem)
        case .unknown:
            break
        @unknown default:
            break
        }

        try await withCheckedThrowingContinuation { continuation in
            readinessContinuation = continuation
            let observation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch item.status {
                    case .readyToPlay:
                        self.completeReadinessWait(with: .success(()))
                    case .failed:
                        self.completeReadinessWait(with: .failure(self.readinessError(for: item)))
                    case .unknown:
                        break
                    @unknown default:
                        break
                    }
                }
            }
            if readinessContinuation == nil {
                observation.invalidate()
            } else {
                readinessObservation = observation
            }
        }
    }

    private func readinessError(for playerItem: AVPlayerItem) -> JellyfinError {
        JellyfinError.requestFailed(playerItem.error?.localizedDescription ?? "The media could not be prepared for playback.")
    }

    private func completeReadinessWait(with result: Result<Void, Error>) {
        readinessObservation?.invalidate()
        readinessObservation = nil
        let continuation = readinessContinuation
        readinessContinuation = nil
        continuation?.resume(with: result)
    }

    private func cancelReadinessWait() {
        completeReadinessWait(with: .failure(CancellationError()))
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
