import SwiftUI

struct LoginView: View {
    @ObservedObject var session: JellyfinSession
    @ObservedObject var seerrSession: SeerrSession
    @State private var serverURL = ""
    @State private var seerrURL = ""
    @State private var username = ""
    @State private var password = ""

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
                Section {
                    Button(session.isWorking || seerrSession.isWorking ? "Signing in…" : "Sign In") {
                        Task {
                            // Keep this view alive until the optional Seerr session has been
                            // persisted. A successful Jellyfin login replaces LoginView.
                            await signInToSeerrIfProvided()
                            await session.login(
                                url: serverURL,
                                username: username,
                                password: password,
                                permitsLocalHTTP: true
                            )
                        }
                    }
                    .disabled(session.isWorking || seerrSession.isWorking || serverURL.isEmpty || username.isEmpty)
                }
            }
            .navigationTitle("Jelly TV")
        }
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
