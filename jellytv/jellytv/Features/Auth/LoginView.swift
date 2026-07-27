import SwiftUI

struct LoginView: View {
    @ObservedObject var session: JellyfinSession
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var allowsLocalHTTP = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Jellyfin server") {
                    TextField("https://jellyfin.example.com", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    Toggle("Allow HTTP for local development", isOn: $allowsLocalHTTP)
                    if allowsLocalHTTP {
                        Text("Use only for a server on your local network.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Sign in") {
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
                    Button(session.isWorking ? "Signing in…" : "Sign In") {
                        Task {
                            await session.login(
                                url: serverURL,
                                username: username,
                                password: password,
                                permitsLocalHTTP: allowsLocalHTTP
                            )
                        }
                    }
                    .disabled(session.isWorking || serverURL.isEmpty || username.isEmpty)
                }
            }
            .navigationTitle("Jelly TV")
        }
    }
}
