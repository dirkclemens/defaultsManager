//
//  defaultsManagerApp.swift
//  defaultsManager
//

import SwiftUI

@main
struct defaultsManagerApp: App {
    @StateObject private var store = DefaultsStore()
    @StateObject private var backupManager = BackupManager()
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var favoritesStore = FavoritesStore()

    init() {
        UpdateChecker.checkForUpdate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(backupManager)
                .environmentObject(sessionStore)
                .environmentObject(favoritesStore)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
