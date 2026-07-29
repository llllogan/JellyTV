import SwiftUI

struct ServicesView: View {
    @ObservedObject var jellyfinSession: JellyfinSession
    @ObservedObject var seerrSession: SeerrSession
    @Environment(\.dismiss) private var dismiss
    @State private var showSeerrConnection = false
    @State private var jellyfinReachability: JellyfinReachability?
    @State private var seerrReachable: Bool?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(jellyfinSession.account?.userName ?? jellyfinSession.account?.userID ?? "Not signed in to Jellyfin", systemImage: "person")
                    if let user = seerrSession.user {
                        Label(
                            user.canApproveRequests ? "Seerr request approval allowed" : "Seerr request approval not allowed",
                            systemImage: "envelope.stack"
                        )
                    }
                }

                Section("Jellyfin") {
                    VStack(alignment: .leading, spacing: 10) {
                        connectionDetails(
                            state: jellyfinConnectionState,
                            serverURL: jellyfinSession.account?.baseURL
                        )
                        if jellyfinSession.account != nil {
                            Button(role: .destructive) { signOut() } label: {
                                Text("Sign Out").frame(maxWidth: .infinity)
                            }
                                .buttonStyle(.bordered)
                        } else {
                            Button { dismiss() } label: {
                                Text("Connect").frame(maxWidth: .infinity)
                            }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }

                Section("Seerr") {
                    VStack(alignment: .leading, spacing: 10) {
                        connectionDetails(
                            state: seerrConnectionState,
                            serverURL: seerrSession.account?.baseURL
                        )
                        if seerrSession.isConnected {
                            HStack {
                                Button { showSeerrConnection = true } label: {
                                    Text("Edit").frame(maxWidth: .infinity)
                                }
                                    .buttonStyle(.bordered)
                                Button(role: .destructive) { seerrSession.disconnect() } label: {
                                    Text("Disconnect").frame(maxWidth: .infinity)
                                }
                                    .buttonStyle(.bordered)
                            }
                        } else {
                            Button { showSeerrConnection = true } label: {
                                Text("Connect").frame(maxWidth: .infinity)
                            }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .navigationTitle("Services")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
            .sheet(isPresented: $showSeerrConnection) { SeerrConnectionView(session: seerrSession) }
            .task(id: jellyfinSession.account?.token) { await refreshJellyfinReachability() }
            .task(id: seerrSession.account?.baseURL) { await refreshSeerrReachability() }
        }
    }

    @ViewBuilder
    private func connectionDetails(state: ConnectionState, serverURL: URL?) -> some View {
        HStack {
            Circle().fill(state.color).frame(width: 10, height: 10)
            Text(state.title)
        }
        Text(serverURL?.absoluteString ?? "Not connected")
            .foregroundStyle(.secondary)
    }

    private var jellyfinConnectionState: ConnectionState {
        guard jellyfinSession.account != nil else { return jellyfinSession.error == nil ? .notConnected : .disconnected }
        return jellyfinReachability == .unreachable ? .disconnected : .connected
    }

    private var seerrConnectionState: ConnectionState {
        guard seerrSession.isConnected else { return seerrSession.error == nil ? .notConnected : .disconnected }
        return seerrReachable == false ? .disconnected : .connected
    }

    private func refreshJellyfinReachability() async {
        jellyfinReachability = await jellyfinSession.refreshReachability()
    }

    private func refreshSeerrReachability() async {
        guard let api = seerrSession.api else {
            seerrReachable = nil
            return
        }

        do {
            _ = try await api.currentUser()
            seerrReachable = true
        } catch {
            seerrReachable = false
            seerrSession.handle(error)
        }
    }

    private func signOut() {
        seerrSession.disconnect()
        jellyfinSession.logout()
        dismiss()
    }

}

private enum ConnectionState {
    case connected
    case disconnected
    case notConnected

    var title: String {
        switch self {
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .notConnected: "Not connected"
        }
    }

    var color: Color {
        switch self {
        case .connected: .green
        case .disconnected: .orange
        case .notConnected: .gray
        }
    }
}

#Preview("Services") {
    ServicesViewPreview()
}

private struct ServicesViewPreview: View {
    @StateObject private var jellyfinSession: JellyfinSession
    @StateObject private var seerrSession = SeerrSession()

    init() {
        let session = JellyfinSession()
        session.account = Account(
            token: "preview-token",
            userID: "preview-user",
            serverID: "preview-server",
            baseURL: URL(string: "https://jellyfin.example.com")!
        )
        _jellyfinSession = StateObject(wrappedValue: session)
    }

    var body: some View {
        ServicesView(jellyfinSession: jellyfinSession, seerrSession: seerrSession)
    }
}
