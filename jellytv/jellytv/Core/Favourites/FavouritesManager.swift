import Combine
import Foundation

struct FavouriteMedia: Codable, Identifiable {
    let item: JellyfinItem
    let serverID: String
    let userID: String
    let addedAt: Date

    var id: String { "\(serverID)|\(userID)|\(item.id)" }
}

@MainActor
final class FavouritesManager: ObservableObject {
    static let shared = FavouritesManager()

    @Published private(set) var records: [FavouriteMedia] = []

    private init() {
        load()
    }

    func items(for account: Account?) -> [JellyfinItem] {
        guard let account else { return [] }
        return records
            .filter { $0.serverID == account.serverID && $0.userID == account.userID }
            .sorted { $0.addedAt > $1.addedAt }
            .map(\.item)
    }

    func contains(_ item: JellyfinItem, account: Account?) -> Bool {
        guard let account else { return false }
        return records.contains { $0.item.id == item.id && $0.serverID == account.serverID && $0.userID == account.userID }
    }

    func toggle(_ item: JellyfinItem, account: Account?) {
        if contains(item, account: account) {
            unfavourite(item, account: account)
        } else {
            favourite(item, account: account)
        }
    }

    func favourite(_ item: JellyfinItem, account: Account?) {
        guard let account, isSupported(item), !contains(item, account: account) else { return }
        records.append(.init(item: item, serverID: account.serverID, userID: account.userID, addedAt: .now))
        persist()
    }

    func unfavourite(_ item: JellyfinItem, account: Account?) {
        guard let account else { return }
        records.removeAll { $0.item.id == item.id && $0.serverID == account.serverID && $0.userID == account.userID }
        persist()
    }

    func isSupported(_ item: JellyfinItem) -> Bool {
        switch item.type {
        case "Movie", "Series", "Season", "Episode": true
        default: false
        }
    }

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appending(path: "Favourites")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private var metadataURL: URL { directory.appending(path: "favourites.json") }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let saved = try? JSONDecoder().decode([FavouriteMedia].self, from: data)
        else { return }
        records = saved
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }
}
