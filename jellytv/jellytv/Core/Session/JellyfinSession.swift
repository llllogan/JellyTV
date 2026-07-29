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

    static var sharedAccount: Account?

    var api: JellyfinAPI? {
        account.map(JellyfinAPI.init)
    }

    var isReachable: Bool {
        reachability == .reachable
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
