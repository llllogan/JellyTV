import Foundation
import Security
import Combine

@MainActor final class JellyfinSession: ObservableObject {
    @Published var account: Account? { didSet { Self.sharedAccount = account } }
    @Published var isWorking = false; @Published var isRestoring = true; @Published var error: String?
    static var sharedAccount: Account?
    var api: JellyfinAPI? { account.map(JellyfinAPI.init) }
    func restore() async { defer { isRestoring = false }; account = KeychainStore.load() }
    func login(url: String, username: String, password: String, permitsLocalHTTP: Bool) async {
        isWorking = true; error = nil; defer { isWorking = false }
        do { let value = try await JellyfinAPI.authenticate(url: url, username: username, password: password, permitsLocalHTTP: permitsLocalHTTP); KeychainStore.save(value); account = value }
        catch { self.error = error.localizedDescription }
    }
    func logout() { KeychainStore.clear(); account = nil; error = nil }
    func handle(_ failure: Error) { if case JellyfinError.unauthorized = failure { logout(); error = failure.localizedDescription } }
}

enum KeychainStore {
    private static let service = "com.logan.jellytv.session", account = "current"
    static func save(_ value: Account) { guard let data = try? JSONEncoder().encode(value) else { return }; clear(); SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecValueData: data] as CFDictionary, nil) }
    static func load() -> Account? { var result: CFTypeRef?; let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecReturnData: true] as CFDictionary, &result); guard status == errSecSuccess, let data = result as? Data else { return nil }; return try? JSONDecoder().decode(Account.self, from: data) }
    static func clear() { SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary) }
}
