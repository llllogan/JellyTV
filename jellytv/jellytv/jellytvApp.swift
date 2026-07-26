//
//  jellytvApp.swift
//  jellytv
//
//  Created by Logan Janssen | Codify on 27/7/2026.
//

import SwiftUI

@main
struct jellytvApp: App {
    @StateObject private var player = PlayerCoordinator()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .sheet(isPresented: $player.isPresenting) { PlayerSheet(coordinator: player) }
        }
    }
}
