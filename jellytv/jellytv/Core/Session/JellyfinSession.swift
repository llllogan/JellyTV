import Combine
import Foundation
import Security

@MainActor
final class JellyfinSession: ObservableObject {
    @Published var account: Account? {
        didSet { Self.sharedAccount = account }
    }
    @Published var isWorking = false
    @Published var isRestoring = true
    @Published var error: String?
    @Published private(set) var reachability: JellyfinReachability?
    @Published private(set) var isRescanningLibraries = false
    @Published private(set) var libraryRescanProgress = 0.0

    static var sharedAccount: Account?

    var api: JellyfinAPI? {
        account.map(JellyfinAPI.init)
    }

    var isReachable: Bool {
        reachability == .reachable
    }

    var canViewStorage: Bool {
        account?.isAdministrator == true
    }

    func restore() async {
        defer { isRestoring = false }
        account = KeychainStore.load()
        guard let account,
              account.userName == nil || account.isAdministrator == nil,
              let user = try? await JellyfinAPI(account: account).currentUser()
        else { return }
        let updatedAccount = Account(
            token: account.token,
            userID: account.userID,
            serverID: account.serverID,
            baseURL: account.baseURL,
            userName: user.name ?? account.userName,
            isAdministrator: user.policy?.isAdministrator ?? account.isAdministrator
        )
        KeychainStore.save(updatedAccount)
        self.account = updatedAccount
    }

    func login(url: String, username: String, password: String, permitsLocalHTTP: Bool) async {
        isWorking = true
        error = nil
        defer { isWorking = false }

        do {
            let account = try await JellyfinAPI.authenticate(
                url: url,
                username: username,
                password: password,
                permitsLocalHTTP: permitsLocalHTTP
            )
            KeychainStore.save(account)
            self.account = account
        } catch {
            self.error = error.localizedDescription
        }
    }

    func logout() {
        KeychainStore.clear()
        account = nil
        reachability = nil
        error = nil
    }

    @discardableResult
    func refreshReachability() async -> JellyfinReachability? {
        guard let api else {
            reachability = nil
            return nil
        }

        let result = await api.reachability()
        reachability = result
        if result == .unauthorized {
            handle(JellyfinError.unauthorized)
        }
        return result
    }

    func handle(_ failure: Error) {
        if case JellyfinError.unauthorized = failure {
            logout()
            error = failure.localizedDescription
        }
    }

    func rescanLibraries() async {
        guard !isRescanningLibraries, let api else { return }
        isRescanningLibraries = true
        libraryRescanProgress = 0

        do {
            try await api.refreshLibraries()
            await monitorLibraryRescan(using: api)
        } catch {
            handle(error)
            isRescanningLibraries = false
        }
    }

    private func monitorLibraryRescan(using api: JellyfinAPI) async {
        var scanWasRunning = false

        for attempt in 0 ..< 3_600 {
            do {
                if let task = try await api.libraryRefreshTask() {
                    if task.isRunning {
                        scanWasRunning = true
                        libraryRescanProgress = min(max((task.currentProgressPercentage ?? 0) / 100, 0), 1)
                    } else if scanWasRunning || attempt >= 10 {
                        isRescanningLibraries = false
                        return
                    }
                } else if attempt >= 10 {
                    isRescanningLibraries = false
                    return
                }
                try await Task.sleep(for: .seconds(1))
            } catch {
                handle(error)
                isRescanningLibraries = false
                return
            }
        }

        isRescanningLibraries = false
    }
}

enum KeychainStore {
    private static let service = "com.logan.jellytv.session"
    private static let account = "current"

    static func save(_ value: Account) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        clear()

        SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
        ] as CFDictionary, nil)
    }

    static func load() -> Account? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
        ] as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Account.self, from: data)
    }

    static func clear() {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary)
    }
}
