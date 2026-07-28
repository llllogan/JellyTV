import SwiftUI

struct ServersView: View {
    @ObservedObject var jellyfinSession: JellyfinSession
    @ObservedObject var seerrSession: SeerrSession
    @Environment(\.dismiss) private var dismiss
    @State private var showSeerrConnection = false
    @State private var jellyfinReachability: JellyfinReachability?
    @State private var isRefreshingLibraries = false
    @State private var libraryRefreshMessage: String?
    @State private var libraryRefreshProgress: Double?

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

                if jellyfinSession.account?.isAdministrator == true {
                    Section("Library") {
                        Button("Refresh All Libraries") { Task { await refreshLibraries() } }
                            .disabled(isRefreshingLibraries)
                        if isRefreshingLibraries {
                            if let libraryRefreshProgress {
                                ProgressView(value: libraryRefreshProgress) {
                                    Text(libraryRefreshMessage ?? "Refreshing library…")
                                } currentValueLabel: {
                                    Text("\(Int(libraryRefreshProgress * 100))%")
                                }
                            } else {
                                ProgressView(libraryRefreshMessage ?? "Starting library refresh…")
                            }
                        }
                        if let libraryRefreshMessage {
                            if isRefreshingLibraries || libraryRefreshMessage.hasPrefix("Library refresh completed") || libraryRefreshMessage.hasPrefix("Library refresh started") {
                                Text(libraryRefreshMessage).foregroundStyle(.secondary)
                            } else {
                                Text(libraryRefreshMessage).foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Servers")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
            .sheet(isPresented: $showSeerrConnection) { SeerrConnectionView(session: seerrSession) }
            .task(id: jellyfinSession.account?.token) { await refreshJellyfinReachability() }
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
        return .connected
    }

    private func refreshJellyfinReachability() async {
        guard let api = jellyfinSession.api else {
            jellyfinReachability = nil
            return
        }
        jellyfinReachability = await api.reachability()
    }

    private func signOut() {
        seerrSession.disconnect()
        jellyfinSession.logout()
        dismiss()
    }

    private func refreshLibraries() async {
        guard let api = jellyfinSession.api else { return }
        isRefreshingLibraries = true
        libraryRefreshMessage = nil
        libraryRefreshProgress = nil
        do {
            try await api.refreshLibraries()
            await monitorLibraryRefresh(using: api)
        } catch {
            jellyfinSession.handle(error)
            libraryRefreshMessage = error.localizedDescription
            isRefreshingLibraries = false
        }
    }

    private func monitorLibraryRefresh(using api: JellyfinAPI) async {
        var refreshWasRunning = false

        for attempt in 0 ..< 3_600 {
            do {
                if let task = try await api.libraryRefreshTask() {
                    if task.isRunning {
                        refreshWasRunning = true
                        let progress = min(max((task.currentProgressPercentage ?? 0) / 100, 0), 1)
                        libraryRefreshProgress = progress
                        libraryRefreshMessage = "Refreshing library…"
                    } else if refreshWasRunning {
                        libraryRefreshProgress = 1
                        libraryRefreshMessage = "Library refresh completed."
                        isRefreshingLibraries = false
                        return
                    } else if attempt >= 10 {
                        libraryRefreshMessage = "Library refresh started. Progress is unavailable."
                        isRefreshingLibraries = false
                        return
                    }
                } else if attempt >= 10 {
                    libraryRefreshMessage = "Library refresh started. Progress is unavailable."
                    isRefreshingLibraries = false
                    return
                }
                try await Task.sleep(for: .seconds(1))
            } catch {
                jellyfinSession.handle(error)
                libraryRefreshMessage = error.localizedDescription
                isRefreshingLibraries = false
                return
            }
        }

        libraryRefreshMessage = "Library refresh is still running."
        isRefreshingLibraries = false
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

#Preview("Servers") {
    ServersViewPreview()
}

private struct ServersViewPreview: View {
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
        ServersView(jellyfinSession: jellyfinSession, seerrSession: seerrSession)
    }
}
