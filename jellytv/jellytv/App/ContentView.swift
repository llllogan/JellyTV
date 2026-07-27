import SwiftUI

struct ContentView: View {
    @StateObject private var session = JellyfinSession()

    var body: some View {
        Group {
            if session.isRestoring {
                ProgressView("Restoring session…")
            } else if session.account == nil {
                LoginView(session: session)
            } else {
                MainTabView(session: session)
            }
        }
        .environmentObject(session)
        .task { await session.restore() }
    }
}

#Preview {
    ContentView()
}
