import SwiftUI

struct BrowseView: View {
    @ObservedObject var session: JellyfinSession
    @State private var resume: [JellyfinItem] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if !resume.isEmpty {
                    Section("Continue Watching") {
                        ForEach(resume) { ItemRow(item: $0) }
                    }
                } else if error == nil {
                    ContentUnavailableView(
                        "Nothing to continue",
                        systemImage: "play.circle",
                        description: Text("Start a movie or show and it will appear here.")
                    )
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") { session.logout() }
                }
            }
            .navigationTitle("Browse")
            .task { await load() }
        }
    }

    private func load() async {
        guard let api = session.api else { return }
        do {
            resume = try await api.resumeItems()
            error = nil
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }
    }
}
