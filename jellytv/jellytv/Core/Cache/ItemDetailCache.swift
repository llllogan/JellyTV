import Foundation
import Combine

@MainActor
final class ItemDetailCache: ObservableObject {
    struct Entry {
        let details: JellyfinItem
        let children: [JellyfinItem]
        let hierarchyParent: JellyfinItem?
        let serverReachable: Bool
    }

    private var entries: [String: Entry] = [:]

    func entry(for itemID: String, account: Account?) -> Entry? {
        entries[key(for: itemID, account: account)]
    }

    func store(_ entry: Entry, for itemID: String, account: Account?) {
        entries[key(for: itemID, account: account)] = entry
    }

    func removeAll() {
        entries.removeAll()
    }

    private func key(for itemID: String, account: Account?) -> String {
        "\(account?.serverID ?? "")|\(account?.userID ?? "")|\(itemID)"
    }
}
