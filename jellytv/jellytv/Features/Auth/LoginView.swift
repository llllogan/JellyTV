import SwiftUI

struct LoginView: View {
    @ObservedObject var session: JellyfinSession
    @ObservedObject var seerrSession: SeerrSession
    @State private var serverURL = ""
    @State private var seerrURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var previousLogins = LoginHistoryStore.load()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Jellyfin URL", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("Seerr URL (optional)", text: $seerrURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password (optional)", text: $password)
                }
                if let error = session.error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .toolbar {
                if !previousLogins.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            ForEach(previousLogins) { login in
                                Button {
                                    serverURL = login.jellyfinURL
                                    seerrURL = login.seerrURL
                                    username = login.username
                                    password = ""
                                } label: {
                                    Text(login.username)
                                    Text(login.jellyfinURL)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Jelly TV")
                        .font(.title3)
                        .bold()
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await signIn() }
                } label: {
                    Text(session.isWorking || seerrSession.isWorking ? "Signing in…" : "Sign In")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .disabled(session.isWorking || seerrSession.isWorking || serverURL.isEmpty || username.isEmpty)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func signIn() async {
        // Keep this view alive until the optional Seerr session has been persisted.
        // A successful Jellyfin login replaces LoginView.
        await signInToSeerrIfProvided()
        await session.login(
            url: serverURL,
            username: username,
            password: password,
            permitsLocalHTTP: true
        )
        guard session.account != nil else { return }
        LoginHistoryStore.save(
            jellyfinURL: serverURL,
            seerrURL: seerrURL,
            username: username
        )
        previousLogins = LoginHistoryStore.load()
    }

    private func signInToSeerrIfProvided() async {
        let url = seerrURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        _ = await seerrSession.connectWithJellyfin(
            url: url,
            username: username,
            password: password,
            permitsLocalHTTP: true
        )
    }
}

private struct PreviousLogin: Codable, Identifiable {
    let id: UUID
    let jellyfinURL: String
    let seerrURL: String
    let username: String
}

private enum LoginHistoryStore {
    private static let storageKey = "previous-logins"

    static func load() -> [PreviousLogin] {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let logins = try? JSONDecoder().decode([PreviousLogin].self, from: data)
        else { return [] }
        return logins
    }

    static func save(jellyfinURL: String, seerrURL: String, username: String) {
        var logins = load()
        guard !logins.contains(where: {
            $0.jellyfinURL == jellyfinURL
                && $0.seerrURL == seerrURL
                && $0.username == username
        }) else { return }

        logins.insert(
            PreviousLogin(
                id: UUID(),
                jellyfinURL: jellyfinURL,
                seerrURL: seerrURL,
                username: username
            ),
            at: 0
        )
        guard let data = try? JSONEncoder().encode(logins) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
