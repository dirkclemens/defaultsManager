//
//  defaultsManagerApp.swift
//  defaultsManager
//

import SwiftUI

@main
struct defaultsManagerApp: App {
    @StateObject private var store = DefaultsStore()
    @StateObject private var backupManager = BackupManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(backupManager)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
