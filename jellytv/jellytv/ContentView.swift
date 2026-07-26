import SwiftUI

struct ContentView: View {
    @StateObject private var session = JellyfinSession()

    var body: some View {
        Group {
            if session.isRestoring { ProgressView("Restoring session…") }
            else if session.account == nil { LoginView(session: session) }
            else { LibraryView(session: session) }
        }
        .environmentObject(session)
        .task { await session.restore() }
    }
}

private struct LoginView: View {
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
                        .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                    Toggle("Allow HTTP for local development", isOn: $allowsLocalHTTP)
                    if allowsLocalHTTP { Text("Use only for a server on your local network.").font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Sign in") {
                    TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password (optional)", text: $password)
                }
                if let error = session.error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button(session.isWorking ? "Signing in…" : "Sign In") {
                        Task { await session.login(url: serverURL, username: username, password: password, permitsLocalHTTP: allowsLocalHTTP) }
                    }.disabled(session.isWorking || serverURL.isEmpty || username.isEmpty)
                }
            }
            .navigationTitle("Jelly TV")
        }
    }
}

struct LibraryView: View {
    @ObservedObject var session: JellyfinSession
    @State private var items: [JellyfinItem] = []
    @State private var resume: [JellyfinItem] = []
    @State private var search = ""
    @State private var selectedType = "Movie"
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if !resume.isEmpty && search.isEmpty {
                    Section("Continue Watching") { ForEach(resume) { ItemRow(item: $0) } }
                }
                Section(selectedType == "Movie" ? "Movies" : "Shows") {
                    ForEach(items) { ItemRow(item: $0) }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .overlay { if items.isEmpty && error == nil { ProgressView() } }
            .searchable(text: $search, prompt: "Search your library")
            .onSubmit(of: .search) { Task { await load() } }
            .onChange(of: selectedType) { _, _ in Task { await load() } }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Library", selection: $selectedType) { Text("Movies").tag("Movie"); Text("Shows").tag("Series") }.pickerStyle(.segmented).frame(width: 180)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Sign Out") { session.logout() } }
            }
            .navigationTitle("Jelly TV")
            .task { await load() }
        }
    }

    private func load() async {
        guard let api = session.api else { return }
        do {
            async let current = api.items(type: selectedType, search: search.isEmpty ? nil : search)
            async let continuing = api.resumeItems()
            items = try await current
            resume = try await continuing
            error = nil
        } catch { session.handle(error); self.error = error.localizedDescription }
    }
}

private struct ItemRow: View {
    let item: JellyfinItem
    var body: some View {
        NavigationLink { ItemDetailView(item: item) } label: {
            HStack(spacing: 12) {
                ArtworkView(item: item, width: 70, height: 100)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name).font(.headline)
                    Text(item.detailLine).font(.subheadline).foregroundStyle(.secondary)
                    if let percent = item.progressPercent { ProgressView(value: percent).tint(.orange) }
                }
            }.padding(.vertical, 3)
        }
    }
}

struct ItemDetailView: View {
    let item: JellyfinItem
    @EnvironmentObject private var player: PlayerCoordinator
    @EnvironmentObject private var session: JellyfinSession
    @State private var details: JellyfinItem?
    @State private var children: [JellyfinItem] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ArtworkView(item: item, width: 180, height: 270).frame(maxWidth: .infinity)
                Text((details ?? item).name).font(.title.bold())
                if let overview = (details ?? item).overview { Text(overview).foregroundStyle(.secondary) }
                if item.type == "Movie" || item.type == "Episode" {
                    Button { Task { await play(details ?? item) } } label: { Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                }
                ForEach(children) { child in ItemRow(item: child) }
                if let error { Text(error).foregroundStyle(.red) }
            }.padding()
        }
        .navigationTitle(item.type == "Series" ? "Show" : "Details").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        guard let api = session.api else { return }
        do {
            details = try await api.item(id: item.id)
            if item.type == "Series" { children = try await api.children(parentID: item.id, type: "Season") }
            else if item.type == "Season" { children = try await api.children(parentID: item.id, type: "Episode") }
        } catch { session.handle(error); self.error = error.localizedDescription }
    }
    private func play(_ target: JellyfinItem) async {
        guard let api = session.api else { return }
        do { try await player.play(item: target, api: api) } catch { self.error = error.localizedDescription }
    }
}

private struct ArtworkView: View {
    let item: JellyfinItem; let width: CGFloat; let height: CGFloat
    var body: some View {
        AsyncImage(url: item.imageURL) { image in image.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.18).overlay(Image(systemName: "film")) }
            .frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview { ContentView() }
