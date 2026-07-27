@preconcurrency import AVFoundation
import Combine
import Foundation

enum OfflineDownloadState: Codable, Equatable {
    case notDownloaded
    case downloading(Double)
    case downloaded
    case failed(String)
}

struct OfflineMedia: Codable, Identifiable {
    let item: JellyfinItem
    let serverID: String
    let userID: String
    var state: OfflineDownloadState
    var assetPath: String?
    var artworkPath: String?
    var taskIdentifier: Int?
    var playbackPositionTicks: Int64
    var downloadedBytes: Int64? = nil
    var contentSizeBytes: Int64? = nil

    var id: String { "\(serverID)|\(userID)|\(item.id)" }
}

/// Stores HLS downloads separately from credentials. Signing out never removes this library.
@MainActor
final class OfflineDownloadManager: NSObject, ObservableObject {
    static let shared = OfflineDownloadManager()

    @Published private(set) var records: [OfflineMedia] = []

    private let sessionIdentifier = "com.logan.jellytv.offline-downloads"
    private var backgroundCompletion: (() -> Void)?
    private lazy var downloadSession: AVAssetDownloadURLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        configuration.allowsCellularAccess = true
        return AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: self, delegateQueue: .main)
    }()

    private override init() {
        super.init()
        load()
        reconnectTasks()
    }

    func state(for itemID: String, account: Account?) -> OfflineDownloadState {
        guard let record = record(for: itemID, account: account) else { return .notDownloaded }
        if case .downloaded = record.state, localAssetURL(for: record) == nil {
            removeRecord(record.id)
            return .notDownloaded
        }
        return record.state
    }

    func downloadedItems(for account: Account?) -> [JellyfinItem] {
        guard let account else { return [] }
        return records.compactMap { record in
            guard record.serverID == account.serverID, record.userID == account.userID,
                  case .downloaded = record.state,
                  localAssetURL(for: record) != nil else { return nil }
            return record.item
        }
    }

    func localAssetURL(itemID: String, account: Account?) -> URL? {
        record(for: itemID, account: account).flatMap(localAssetURL)
    }

    func localArtworkURL(itemID: String, account: Account?) -> URL? {
        guard let record = record(for: itemID, account: account), let artworkPath = record.artworkPath else { return nil }
        let url = rootDirectory.appending(path: artworkPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func playbackPosition(itemID: String, account: Account?) -> Int64 {
        record(for: itemID, account: account)?.playbackPositionTicks ?? 0
    }

    func downloadedBytes(itemID: String, account: Account?) -> Int64 {
        record(for: itemID, account: account)?.downloadedBytes ?? 0
    }

    func contentSizeBytes(itemID: String, account: Account?) -> Int64? {
        guard let record = record(for: itemID, account: account) else { return nil }
        if let size = record.contentSizeBytes { return size }
        if let url = localAssetURL(for: record) {
            let size = directorySize(at: url)
            if size > 0 { return size }
        }
        return record.item.size ?? record.item.mediaSources?.first?.size
    }

    func downloadedEpisodeCount(in season: JellyfinItem, account: Account?) -> Int {
        guard let account else { return 0 }
        return records.count {
            guard $0.serverID == account.serverID, $0.userID == account.userID,
                  $0.item.type == "Episode", $0.state == .downloaded else { return false }

            if $0.item.seasonID == season.id || $0.item.parentID == season.id { return true }
            return $0.item.seriesID == season.parentID &&
                $0.item.parentIndexNumber == season.indexNumber
        }
    }

    func download(_ item: JellyfinItem, api: JellyfinAPI, audioStreamIndex: Int? = nil) async {
        guard item.type == "Movie" || item.type == "Episode" else { return }
        removeExisting(itemID: item.id, account: api.account, keepFiles: false)
        do {
            let info = try await api.playbackInfo(
                itemID: item.id,
                positionTicks: item.userData?.playbackPositionTicks ?? 0,
                audioStreamIndex: audioStreamIndex
            )
            guard let source = info.mediaSources.first else { throw JellyfinError.requestFailed("No playable media source was returned.") }
            let asset = AVURLAsset(url: api.playbackURL(itemID: item.id, source: source, audioStreamIndex: audioStreamIndex), options: [
                "AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "MediaBrowser Token=\"\(api.account.token)\""]
            ])
            let task = downloadSession.makeAssetDownloadTask(asset: asset, assetTitle: item.name, assetArtworkData: nil, options: nil)
            guard let task else { throw JellyfinError.requestFailed("This media cannot be downloaded by iOS.") }
            var record = OfflineMedia(item: item, serverID: api.account.serverID, userID: api.account.userID, state: .downloading(0), assetPath: nil, artworkPath: nil, taskIdentifier: task.taskIdentifier, playbackPositionTicks: item.userData?.playbackPositionTicks ?? 0, downloadedBytes: task.countOfBytesReceived, contentSizeBytes: nil)
            task.taskDescription = record.id
            records.append(record)
            persist()
            record.artworkPath = await cacheArtwork(item: item, account: api.account, recordID: record.id)
            replace(record)
            task.resume()
        } catch {
            let record = OfflineMedia(item: item, serverID: api.account.serverID, userID: api.account.userID, state: .failed(error.localizedDescription), assetPath: nil, artworkPath: nil, taskIdentifier: nil, playbackPositionTicks: item.userData?.playbackPositionTicks ?? 0)
            records.append(record)
            persist()
        }
    }

    func cancel(itemID: String, account: Account?) {
        guard let record = record(for: itemID, account: account) else { return }
        downloadSession.getAllTasks { tasks in tasks.first(where: { $0.taskIdentifier == record.taskIdentifier })?.cancel() }
        removeRecord(record.id)
    }

    func remove(itemID: String, account: Account?) {
        guard let record = record(for: itemID, account: account) else { return }
        cancel(itemID: itemID, account: account)
        removeFiles(for: record)
    }

    func updatePlayback(itemID: String, account: Account, ticks: Int64) {
        guard var record = record(for: itemID, account: account) else { return }
        record.playbackPositionTicks = max(0, ticks)
        replace(record)
    }

    func queueProgressSync(itemID: String, account: Account, ticks: Int64) {
        updatePlayback(itemID: itemID, account: account, ticks: ticks)
        Task {
            let api = JellyfinAPI(account: account)
            guard await api.isReachable() else { return }
            await api.report("Sessions/Playing/Stopped", itemID: itemID, positionTicks: ticks, playSessionID: nil)
        }
    }

    func syncQueuedProgress(account: Account) async {
        let api = JellyfinAPI(account: account)
        guard await api.isReachable() else { return }
        for record in records where record.serverID == account.serverID && record.userID == account.userID {
            await api.report("Sessions/Playing/Stopped", itemID: record.item.id, positionTicks: record.playbackPositionTicks, playSessionID: nil)
        }
    }

    func setBackgroundCompletion(_ completion: @escaping () -> Void) { backgroundCompletion = completion }

    private var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appending(path: "OfflineLibrary")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private var metadataURL: URL { rootDirectory.appending(path: "downloads.json") }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL), let saved = try? JSONDecoder().decode([OfflineMedia].self, from: data) else { return }
        records = saved.filter { record in
            if case .downloaded = record.state { return localAssetURL(for: record) != nil }
            return true
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func record(for itemID: String, account: Account?) -> OfflineMedia? {
        guard let account else { return nil }
        return records.first { $0.item.id == itemID && $0.serverID == account.serverID && $0.userID == account.userID }
    }

    private func replace(_ record: OfflineMedia) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
        persist()
    }

    private func removeRecord(_ id: String) {
        records.removeAll { $0.id == id }
        persist()
    }

    private func removeExisting(itemID: String, account: Account, keepFiles: Bool) {
        guard let record = record(for: itemID, account: account) else { return }
        if !keepFiles { removeFiles(for: record) }
        removeRecord(record.id)
    }

    private func removeFiles(for record: OfflineMedia) {
        [record.assetPath, record.artworkPath].compactMap { $0 }.forEach {
            try? FileManager.default.removeItem(at: rootDirectory.appending(path: $0))
        }
    }

    private func localAssetURL(for record: OfflineMedia) -> URL? {
        guard let path = record.assetPath else { return nil }
        let url = rootDirectory.appending(path: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func cacheArtwork(item: JellyfinItem, account: Account, recordID: String) async -> String? {
        guard let url = item.imageURL else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url), (response as? HTTPURLResponse)?.statusCode ?? 0 < 300 else { return nil }
        let filename = "\(safeFilename(recordID)).jpg"
        try? data.write(to: rootDirectory.appending(path: filename), options: .atomic)
        return filename
    }

    private func safeFilename(_ value: String) -> String { value.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "|", with: "_") }

    private func reconnectTasks() {
        downloadSession.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                guard let self else { return }
                for task in tasks {
                    guard let id = task.taskDescription, var record = self.records.first(where: { $0.id == id }) else { continue }
                    record.taskIdentifier = task.taskIdentifier
                    record.downloadedBytes = task.countOfBytesReceived
                    if task.state == .running { record.state = .downloading(task.progress.fractionCompleted) }
                    self.replace(record)
                }
            }
        }
    }
}

extension OfflineDownloadManager: AVAssetDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        let progress = loadedTimeRanges.reduce(0) { $0 + $1.timeRangeValue.duration.seconds } / max(timeRangeExpectedToLoad.duration.seconds, 1)
        Task { @MainActor in
            guard let id = assetDownloadTask.taskDescription, var record = self.records.first(where: { $0.id == id }) else { return }
            record.state = .downloading(min(max(progress, 0), 1))
            record.downloadedBytes = assetDownloadTask.countOfBytesReceived
            self.replace(record)
        }
    }

    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        Task { @MainActor in
            guard let id = assetDownloadTask.taskDescription, var record = self.records.first(where: { $0.id == id }) else { return }
            let filename = "\(self.safeFilename(id)).movpkg"
            let destination = self.rootDirectory.appending(path: filename)
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.moveItem(at: location, to: destination)
                record.assetPath = filename
                record.taskIdentifier = nil
                record.contentSizeBytes = self.directorySize(at: destination)
                record.downloadedBytes = record.contentSizeBytes
                record.state = .downloaded
            } catch { record.state = .failed("Unable to save the downloaded media.") }
            self.replace(record)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            guard let id = task.taskDescription, var record = self.records.first(where: { $0.id == id }) else { return }
            if (error as NSError).code == NSURLErrorCancelled { self.removeRecord(id) }
            else { record.state = .failed(error.localizedDescription); record.taskIdentifier = nil; self.replace(record) }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            let completion = self.backgroundCompletion
            self.backgroundCompletion = nil
            completion?()
        }
    }
}

private extension OfflineDownloadManager {
    func directorySize(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey]
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        return enumerator?.reduce(Int64(0)) { total, entry in
            guard let file = entry as? URL,
                  let values = try? file.resourceValues(forKeys: keys) else { return total }
            return total + Int64(values.fileSize ?? 0)
        } ?? 0
    }
}
