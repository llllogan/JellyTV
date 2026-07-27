import SwiftUI

struct SeerrConnectionView: View {
    @ObservedObject var session: SeerrSession
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var apiKey = ""
    @State private var usesAPIKey = false
    @State private var allowsLocalHTTP = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Seerr server") {
                    TextField("https://seerr.example.com", text: $serverURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Toggle("Allow HTTP for local development", isOn: $allowsLocalHTTP)
                }
                Section("Sign in") {
                    Picker("Method", selection: $usesAPIKey) {
                        Text("Jellyfin account").tag(false)
                        Text("Personal API key").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if usesAPIKey {
                        SecureField("Seerr API key", text: $apiKey)
                    } else {
                        TextField("Jellyfin username", text: $username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Jellyfin password", text: $password)
                        Text("Your password is used only to establish the Seerr session and is not stored.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error = session.error { Section { Text(error).foregroundStyle(.red) } }
                if session.isConnected {
                    Section { Button("Disconnect Seerr", role: .destructive) { session.disconnect() } }
                }
            }
            .navigationTitle("Connect Seerr")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(session.isWorking ? "Connecting…" : "Connect") {
                        Task {
                            let connected = if usesAPIKey {
                                await session.connectWithAPIKey(url: serverURL, apiKey: apiKey, permitsLocalHTTP: allowsLocalHTTP)
                            } else {
                                await session.connectWithJellyfin(url: serverURL, username: username, password: password, permitsLocalHTTP: allowsLocalHTTP)
                            }
                            if connected { dismiss() }
                        }
                    }
                    .disabled(session.isWorking || serverURL.isEmpty || (usesAPIKey ? apiKey.isEmpty : username.isEmpty))
                }
            }
        }
    }
}
