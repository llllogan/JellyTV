import Combine
import Foundation
import Security

@MainActor
final class SeerrSession: ObservableObject {
    @Published private(set) var account: SeerrAccount?
    @Published private(set) var user: SeerrUser?
    @Published private(set) var pendingApprovalCount = 0
    @Published var isWorking = false
    @Published var error: String?

    var api: SeerrAPI? { account.map(SeerrAPI.init) }
    var isConnected: Bool { account != nil }

    func restore() async {
        guard let account = SeerrKeychainStore.load() else { return }
        self.account = account
        await validate()
    }

    func connectWithJellyfin(url: String, username: String, password: String, permitsLocalHTTP: Bool) async -> Bool {
        isWorking = true; error = nil
        defer { isWorking = false }
        do {
            let account = try await SeerrAPI.jellyfinSignIn(url: url, username: username, password: password, permitsLocalHTTP: permitsLocalHTTP)
            try await saveValidated(account)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func connectWithAPIKey(url: String, apiKey: String, permitsLocalHTTP: Bool) async -> Bool {
        isWorking = true; error = nil
        defer { isWorking = false }
        do {
            let account = try SeerrAPI.apiKeyAccount(url: url, apiKey: apiKey, permitsLocalHTTP: permitsLocalHTTP)
            try await saveValidated(account)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func disconnect() {
        SeerrKeychainStore.clear()
        account = nil; user = nil; pendingApprovalCount = 0; error = nil
    }

    func handle(_ failure: Error) {
        if case SeerrError.unauthorized = failure {
            disconnect()
            error = failure.localizedDescription
        }
    }

    func refreshPendingApprovalCount() async {
        guard user?.canApproveRequests == true, let api else {
            pendingApprovalCount = 0
            return
        }
        do {
            pendingApprovalCount = try await api.approvalRequests().count
        } catch {
            pendingApprovalCount = 0
            handle(error)
        }
    }

    private func validate() async {
        guard let api else { return }
        do {
            user = try await api.currentUser()
            await refreshPendingApprovalCount()
        }
        catch { handle(error) }
    }

    private func saveValidated(_ account: SeerrAccount) async throws {
        let user = try await SeerrAPI(account: account).currentUser()
        SeerrKeychainStore.save(account)
        self.account = account
        self.user = user
        await refreshPendingApprovalCount()
    }
}

private enum SeerrKeychainStore {
    static let service = "com.logan.jellytv.seerr-session"
    static let account = "current"
    static func save(_ value: SeerrAccount) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        clear()
        SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecValueData: data] as CFDictionary, nil)
    }
    static func load() -> SeerrAccount? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecReturnData: true] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SeerrAccount.self, from: data)
    }
    static func clear() {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
    }
}
