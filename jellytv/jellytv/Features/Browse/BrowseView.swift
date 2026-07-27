import SwiftUI

struct BrowseView: View {
    @ObservedObject var session: JellyfinSession
    @State private var resume: [JellyfinItem] = []
    @State private var nextUp: [JellyfinItem] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if !resume.isEmpty {
                    Section("Continue Watching") {
                        MediaCarousel(items: resume, detailStyle: .remainingTime)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                if !nextUp.isEmpty {
                    Section("Next Up") {
                        MediaCarousel(items: nextUp, detailStyle: .nextUp)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                if resume.isEmpty && nextUp.isEmpty && error == nil {
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
            .listStyle(.plain)
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
        error = nil

        async let resumeRequest = api.resumeItems()
        async let nextUpRequest = api.nextUpEpisodes()

        do {
            resume = try await resumeRequest
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }

        do {
            nextUp = try await nextUpRequest
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }
    }
}
