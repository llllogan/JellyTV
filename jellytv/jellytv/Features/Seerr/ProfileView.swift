import SwiftUI

struct ProfileView: View {
    @ObservedObject var jellyfinSession: JellyfinSession
    @ObservedObject var seerrSession: SeerrSession
    @Environment(\.dismiss) private var dismiss
    @State private var showSeerrConnection = false

    var body: some View {
        NavigationStack {
            Form {
                if let account = jellyfinSession.account {
                    Section("Jellyfin") {
                        LabeledContent("Server", value: account.baseURL.absoluteString)
                        LabeledContent("User", value: account.userID)
                        LabeledContent("Server ID", value: account.serverID)
                        Button("Sign Out", role: .destructive) {
                            seerrSession.disconnect()
                            jellyfinSession.logout()
                            dismiss()
                        }
                    }
                }

                Section("Seerr") {
                    if let account = seerrSession.account {
                        LabeledContent("Server", value: account.baseURL.absoluteString)
                        if let user = seerrSession.user {
                            LabeledContent("Account", value: user.displayName ?? user.email ?? "Unknown")
                            LabeledContent("Request approval", value: user.canApproveRequests ? "Allowed" : "Not allowed")
                        }
                        LabeledContent("Authentication", value: account.apiKey == nil ? "Jellyfin session" : "Personal API key")
                        Button("Disconnect Seerr", role: .destructive) { seerrSession.disconnect() }
                    } else {
                        Text("Not connected").foregroundStyle(.secondary)
                        Button("Connect Seerr") { showSeerrConnection = true }
                    }
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
            .sheet(isPresented: $showSeerrConnection) { SeerrConnectionView(session: seerrSession) }
        }
    }
}
