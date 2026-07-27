import SwiftUI

struct ContentView: View {
    @StateObject private var session = JellyfinSession()
    @StateObject private var seerrSession = SeerrSession()

    var body: some View {
        Group {
            if session.isRestoring {
                ProgressView("Restoring session…")
            } else if session.account == nil {
                LoginView(session: session, seerrSession: seerrSession)
            } else {
                MainTabView(session: session, seerrSession: seerrSession)
            }
        }
        .environmentObject(session)
        .environmentObject(seerrSession)
        .task {
            await session.restore()
            await seerrSession.restore()
        }
    }
}

#Preview {
    ContentView()
}
