//
//  ContentView.swift
//  defaultsManager
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DefaultsStore
    @EnvironmentObject var backupManager: BackupManager
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var favoritesStore: FavoritesStore

    @State private var sidebarSelection: SidebarItem?
    @State private var selectedEntry: DefaultEntry?
    @State private var searchText = ""
    @State private var showAlert = false
    @State private var showRestoreAllAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @State private var isWorking = false
    @State private var workingMessage = ""
    @State private var showLaunchWarning = true

    var body: some View {
        NavigationSplitView {
            // MARK: Category list (sidebar)
            DomainListView(selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } content: {
            // MARK: Settings list (middle)
            switch sidebarSelection {
            case .favorites:
                FavoritesView(selectedEntry: $selectedEntry)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
            case .changed:
                ChangedView(selectedEntry: $selectedEntry)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
            case .category(let category):
                KeyListView(category: category, selectedEntry: $selectedEntry, searchText: $searchText)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
            case nil:
                ContentUnavailableView("Select a Category", systemImage: "sidebar.left",
                    description: Text("Choose a category from the sidebar to browse its settings."))
            }
        } detail: {
            // MARK: Detail panel (right)
            if let entry = selectedEntry {
                DetailView(entry: entry)
            } else {
                ContentUnavailableView("Select a Setting", systemImage: "gearshape",
                    description: Text("Choose a setting from the list to view and edit its value."))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    backupAll()
                } label: {
                    Label("Backup All", systemImage: "arrow.down.circle")
                }
                .help("Backup the current system state for all \(store.entries.count) settings")

                Button {
                    showRestoreAllAlert = true
                } label: {
                    Label("Restore All", systemImage: "arrow.counterclockwise.circle")
                }
                .help("Restore all settings to their backed-up values")
                .disabled(!backupManager.hasFullBackup)

                Divider()

                Button {
                    store.revealUserFileInFinder()
                } label: {
                    Label("Edit Parameters JSON", systemImage: "doc.badge.gearshape")
                }
                .help("Open macos-defaults.json in Finder — add custom entries and reload the app")
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog("Restore All Settings?", isPresented: $showRestoreAllAlert) {
            Button("Restore All", role: .destructive) { restoreAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore \(backupManager.backedUpDomains.count) domains to their backed-up values.")
        }
        .overlay {
            if store.isLoading || isWorking {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.4)
                        Text(isWorking ? workingMessage : "Loading…")
                            .font(.headline)
                    }
                    .padding(32)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 20)
                }
            }
        }
        .sheet(isPresented: $showLaunchWarning) {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.yellow)

                Text("Proceed with Caution")
                    .font(.title.bold())

                Text("This app lets you modify macOS system defaults — low-level settings that control how macOS behaves.\n\nChanging the wrong value can cause unexpected behaviour, app crashes, or require a system restart to recover.\n\n**Only change a value if you are absolutely sure what it does.**\n\nWhen in doubt, use **Backup All** before making any changes so you can restore to a known-good state.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)

                Button("I Understand — Proceed") {
                    showLaunchWarning = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(40)
            .interactiveDismissDisabled()
        }
    }

    private func backupAll() {
        let domains = Array(Set(store.entries.map(\.domain))).sorted()
        let backupDir = backupManager.domainBackupURL
        workingMessage = "Exporting \(domains.count) domains…"
        isWorking = true
        Task.detached(priority: .userInitiated) {
            let (exported, errors) = await backupManager.exportDomains(domains, to: backupDir)
            await backupManager.recordBackup(exportedDomains: exported)
            await MainActor.run {
                isWorking = false
                if errors.isEmpty {
                    alertTitle = "Backup Complete"
                    alertMessage = "Successfully exported \(exported.count) domains to:\n\(backupDir.path)"
                } else {
                    alertTitle = "Backup Completed with Warnings"
                    alertMessage = "Exported \(exported.count) domains.\n\nSkipped:\n" + errors.joined(separator: "\n")
                }
                showAlert = true
            }
        }
    }

    private func restoreAll() {
        let backupDir = backupManager.domainBackupURL
        let domainCount = backupManager.backedUpDomains.count
        workingMessage = "Restoring \(domainCount) domains…"
        isWorking = true
        Task.detached(priority: .userInitiated) {
            let (restored, errors) = await backupManager.importDomains(from: backupDir)
            await MainActor.run {
                isWorking = false
                if errors.isEmpty {
                    alertTitle = "Restore Complete"
                    alertMessage = "Successfully restored \(restored.count) domains."
                } else {
                    alertTitle = "Restore Completed with Warnings"
                    alertMessage = "Restored \(restored.count) domains.\n\nFailed:\n" + errors.joined(separator: "\n")
                }
                showAlert = true
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DefaultsStore())
        .environmentObject(BackupManager())
        .environmentObject(SessionStore())
        .environmentObject(FavoritesStore())
}
