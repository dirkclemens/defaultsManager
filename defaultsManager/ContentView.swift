//
//  ContentView.swift
//  defaultsManager
//

import SwiftUI

/// Only one `.sheet` per view is reliable in SwiftUI, so all sheets go through this.
enum ActiveSheet: String, Identifiable {
    case launchWarning, restore
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var store: DefaultsStore
    @EnvironmentObject var backupManager: BackupManager
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var favoritesStore: FavoritesStore

    @AppStorage(AppStorageKey.hideLaunchWarning) private var hideLaunchWarning = false

    @State private var sidebarSelection: SidebarItem?
    @State private var selectedEntry: DefaultEntry?
    @State private var searchText = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @State private var isWorking = false
    @State private var workingMessage = ""
    @State private var activeSheet: ActiveSheet? =
        UserDefaults.standard.bool(forKey: AppStorageKey.hideLaunchWarning) ? nil : .launchWarning

    var body: some View {
        NavigationSplitView {
            // MARK: Category list (sidebar)
            DomainListView(selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } content: {
            // MARK: Settings list (middle)
            Group {
                if !searchText.isEmpty {
                    // Global search works regardless of what is selected in the sidebar.
                    KeyListView(category: nil, selectedEntry: $selectedEntry, searchText: searchText)
                } else {
                    switch sidebarSelection {
                    case .favorites:
                        FavoritesView(selectedEntry: $selectedEntry)
                    case .changed:
                        ChangedView(selectedEntry: $selectedEntry)
                    case .category(let category):
                        KeyListView(category: category, selectedEntry: $selectedEntry, searchText: "")
                    case nil:
                        ContentUnavailableView("Select a Category", systemImage: "sidebar.left",
                            description: Text("Choose a category from the sidebar or search all settings."))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            // MARK: Detail panel (right)
            if let entry = selectedEntry {
                DetailView(entry: entry)
                    .id(entry.id)   // fresh @State per entry; avoids stale async results
            } else {
                ContentUnavailableView("Select a Setting", systemImage: "gearshape",
                    description: Text("Choose a setting from the list to view and edit its value."))
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search all settings…")
        .onChange(of: sidebarSelection) { _, _ in
            // Picking something in the sidebar ends a running search.
            searchText = ""
            selectedEntry = nil
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    backupAll()
                } label: {
                    Label("Backup All", systemImage: "arrow.down.circle")
                }
                .help("Save a new timestamped backup of all \(store.entries.count) settings")

                Button {
                    activeSheet = .restore
                } label: {
                    Label("Restore…", systemImage: "arrow.counterclockwise.circle")
                }
                .help("Choose a backup and restore selected settings")
                .disabled(!backupManager.hasFullBackup)

                Divider()

                Button {
                    store.revealUserFileInFinder()
                } label: {
                    Label("Edit Parameters JSON", systemImage: "doc.badge.gearshape")
                }
                .help("Open macos-defaults.json in Finder — add custom entries, then Reload")

                Button {
                    store.loadEntries()
                } label: {
                    Label("Reload Parameters", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Reload macos-defaults.json (⌘R)")
            }
        }
        .alert("Could Not Load Settings", isPresented: Binding(
            get: { store.errorMessage != nil && activeSheet != .launchWarning },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("Show File") { store.revealUserFileInFinder() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
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
        .onReceive(NotificationCenter.default.publisher(for: .showSafetyNotice)) { _ in
            activeSheet = .launchWarning
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .launchWarning: launchWarning
            case .restore:       RestoreBackupView()
            }
        }
    }

    // MARK: - Launch warning

    private var launchWarning: some View {
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

            VStack(spacing: 12) {
                Button("I Understand — Proceed") {
                    activeSheet = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Toggle("Don't show this again", isOn: $hideLaunchWarning)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .help("You can show this notice again from the Help menu.")
            }
        }
        .padding(40)
        .interactiveDismissDisabled()
    }

    // MARK: - Backup

    private func backupAll() {
        let keysByDomain = Dictionary(grouping: store.entries, by: \.domain).mapValues { $0.map(\.key) }
        workingMessage = "Backing up \(keysByDomain.count) domains…"
        isWorking = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                BackupManager.createBackup(keysByDomain: keysByDomain)
            }.value
            backupManager.reloadDomainBackups()
            isWorking = false

            let skipped = result.errors.isEmpty ? "" : "\n\nSkipped:\n" + result.errors.joined(separator: "\n")
            if let backup = result.backup {
                alertTitle = result.errors.isEmpty ? "Backup Complete" : "Backup Completed with Warnings"
                alertMessage = "Saved \(backup.manifest.domains.count) domains to:\n\(backup.folder.path)\n\nEarlier backups are kept — choose one under Restore…" + skipped
            } else {
                alertTitle = "Backup Failed"
                alertMessage = "No domain could be exported." + skipped
            }
            showAlert = true
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
