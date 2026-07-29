//
//  jellytvApp.swift
//  jellytv
//
//  Created by Logan Janssen | Codify on 27/7/2026.
//

import SwiftUI
import UIKit

@main
struct jellytvApp: App {
    @StateObject private var player = PlayerCoordinator()
    @StateObject private var downloads = OfflineDownloadManager.shared
    @StateObject private var favourites = FavouritesManager.shared
    @StateObject private var itemDetailCache = ItemDetailCache()
    @UIApplicationDelegateAdaptor(OfflineDownloadAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .environmentObject(downloads)
                .environmentObject(favourites)
                .environmentObject(itemDetailCache)
                .fullScreenCover(isPresented: $player.isPresenting, onDismiss: {
                    player.stop()
                }) {
                    NativePlayerView(coordinator: player)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, let account = JellyfinSession.sharedAccount {
                        Task { await downloads.syncQueuedProgress(account: account) }
                    }
                }
        }
    }
}

final class OfflineDownloadAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == "com.logan.jellytv.offline-downloads" else { completionHandler(); return }
        OfflineDownloadManager.shared.setBackgroundCompletion(completionHandler)
    }
}
