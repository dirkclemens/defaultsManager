//
//  RestoreBackupView.swift
//  defaultsManager
//
//  Pick one of the timestamped full backups, review which managed settings
//  differ from the live system, and restore a selection of them.
//

import SwiftUI
import AppKit

struct RestoreBackupView: View {
    @EnvironmentObject var store: DefaultsStore
    @EnvironmentObject var backupManager: BackupManager
    @EnvironmentObject var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedBackup: DomainBackup?
    @State private var changes: [RestoreChange] = []
    @State private var selectedIDs: Set<String> = []
    @State private var warnings: [String] = []
    @State private var isComparing = false
    @State private var isRestoring = false
    @State private var backupToTrash: DomainBackup?
    @State private var outcome: RestoreOutcome?

    struct RestoreOutcome: Identifiable {
        let id = UUID()
        let restored: Int
        let errors: [String]
        let restartTargets: [String]
        let needsLogout: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                backupList
                    .frame(width: 240)
                Divider()
                changesPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 780, idealWidth: 860, minHeight: 500, idealHeight: 580)
        .onAppear {
            if selectedBackup == nil { selectedBackup = backupManager.domainBackups.first }
        }
        .task(id: selectedBackup) { await compare() }
        .confirmationDialog("Move this backup to the Trash?",
                            isPresented: Binding(get: { backupToTrash != nil },
                                                 set: { if !$0 { backupToTrash = nil } }),
                            presenting: backupToTrash) { backup in
            Button("Move to Trash", role: .destructive) { trash(backup) }
            Button("Cancel", role: .cancel) {}
        } message: { backup in
            Text("Backup from \(backup.createdAt.formatted(date: .long, time: .standard))")
        }
        .alert(outcome.map { $0.errors.isEmpty ? "Restore Complete" : "Restore Completed with Warnings" } ?? "",
               isPresented: Binding(get: { outcome != nil }, set: { if !$0 { outcome = nil } }),
               presenting: outcome) { result in
            if !result.restartTargets.isEmpty {
                Button("Restart \(result.restartTargets.joined(separator: ", ")) Now") {
                    result.restartTargets.forEach { RestartActionResolver.perform(.killProcess($0)) }
                    dismiss()
                }
            }
            Button("Done") { dismiss() }
        } message: { result in
            Text(outcomeMessage(result))
        }
    }

    // MARK: - Backup list

    private var backupList: some View {
        VStack(spacing: 0) {
            List(backupManager.domainBackups, selection: $selectedBackup) { backup in
                VStack(alignment: .leading, spacing: 2) {
                    Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.body)
                    Text("\(backup.manifest.domains.count) domains" + (backup.manifest.keys == nil ? " · migrated" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(backup)
                .contextMenu {
                    Button("Show in Finder") { reveal(backup) }
                    Button("Move to Trash…", role: .destructive) { backupToTrash = backup }
                }
            }
            Divider()
            HStack {
                Button("", systemImage: "folder") {
                    if let selectedBackup { reveal(selectedBackup) }
                }
                .help("Show backup in Finder")
                Button("", systemImage: "trash") {
                    backupToTrash = selectedBackup
                }
                .help("Move backup to the Trash")
                Spacer()
            }
            .buttonStyle(.borderless)
            .disabled(selectedBackup == nil)
            .padding(8)
        }
    }

    // MARK: - Changes

    @ViewBuilder
    private var changesPane: some View {
        if selectedBackup == nil {
            ContentUnavailableView("No Backup Selected", systemImage: "clock.arrow.circlepath",
                                   description: Text("Choose a backup on the left."))
        } else if isComparing {
            ProgressView("Comparing with current system…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if changes.isEmpty && warnings.isEmpty {
            ContentUnavailableView("Nothing to Restore", systemImage: "checkmark.circle",
                                   description: Text("All managed settings already match this backup."))
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("\(changes.count) setting\(changes.count == 1 ? "" : "s") differ from this backup")
                        .font(.headline)
                    Spacer()
                    Button("Select All") { selectedIDs = Set(changes.map(\.id)) }
                    Button("Select None") { selectedIDs = [] }
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()
                List {
                    if !warnings.isEmpty {
                        Section("Not compared") {
                            ForEach(warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(groupedDomains, id: \.self) { domain in
                        Section(domain) {
                            ForEach(changes.filter { $0.domain == domain }) { change in
                                Toggle(isOn: binding(for: change)) {
                                    changeRow(change)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                }
            }
        }
    }

    private func changeRow(_ change: RestoreChange) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(change.key)
            HStack(spacing: 5) {
                Text(change.currentDisplay)
                    .foregroundStyle(.secondary)
                    .strikethrough()
                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(change.backupDisplay)
            }
            .font(.caption.monospaced())
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .padding(.vertical, 1)
    }

    private var groupedDomains: [String] {
        var seen = Set<String>()
        return changes.map(\.domain).filter { seen.insert($0).inserted }
    }

    private func binding(for change: RestoreChange) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(change.id) },
            set: { on in
                if on { selectedIDs.insert(change.id) } else { selectedIDs.remove(change.id) }
            }
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Label("Only settings listed in defaultsManager are restored — all other keys stay untouched.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if isRestoring { ProgressView().controlSize(.small) }
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Restore \(selectedIDs.count) Setting\(selectedIDs.count == 1 ? "" : "s")") { restore() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIDs.isEmpty || isRestoring || isComparing)
        }
        .padding(12)
    }

    // MARK: - Actions

    private func compare() async {
        changes = []
        selectedIDs = []
        warnings = []
        guard let backup = selectedBackup else { return }
        isComparing = true
        let fallbackKeys = Dictionary(grouping: store.entries, by: \.domain).mapValues { $0.map(\.key) }
        let result = await Task.detached(priority: .userInitiated) {
            BackupManager.differences(for: backup, fallbackKeys: fallbackKeys)
        }.value
        guard !Task.isCancelled, backup == selectedBackup else { return }
        changes = result.changes
        selectedIDs = Set(result.changes.map(\.id))
        warnings = result.errors
        isComparing = false
    }

    private func restore() {
        let chosen = changes.filter { selectedIDs.contains($0.id) }
        isRestoring = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                BackupManager.apply(chosen)
            }.value

            let entriesByID = Dictionary(store.entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var restartTargets = Set<String>()
            var needsLogout = false
            for change in result.applied {
                guard let entry = entriesByID[change.id] else { continue }
                sessionStore.record(entry: entry, oldValue: change.currentDisplay, newValue: change.backupDisplay)
                switch RestartActionResolver.action(for: entry) {
                case .killProcess(let name): restartTargets.insert(name)
                case .logout:                needsLogout = true
                case .none:                  break
                }
            }
            isRestoring = false
            outcome = RestoreOutcome(restored: result.applied.count, errors: result.errors,
                                     restartTargets: restartTargets.sorted(), needsLogout: needsLogout)
        }
    }

    private func outcomeMessage(_ result: RestoreOutcome) -> String {
        var parts = ["Restored \(result.restored) setting\(result.restored == 1 ? "" : "s")."]
        if !result.restartTargets.isEmpty {
            parts.append("Some changes take effect after restarting \(result.restartTargets.joined(separator: ", ")).")
        }
        if result.needsLogout {
            parts.append("Some changes take effect after logging out and back in.")
        }
        if !result.errors.isEmpty {
            parts.append("Failed:\n" + result.errors.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    private func reveal(_ backup: DomainBackup) {
        NSWorkspace.shared.activateFileViewerSelecting([backup.folder])
    }

    private func trash(_ backup: DomainBackup) {
        do {
            try backupManager.trash(backup)
            if selectedBackup == backup { selectedBackup = backupManager.domainBackups.first }
        } catch {
            warnings = ["Could not move backup to the Trash: \(error.localizedDescription)"]
        }
    }
}
