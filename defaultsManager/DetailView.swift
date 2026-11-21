//
//  DetailView.swift
//  defaultsManager
//

import SwiftUI
import Combine

struct DetailView: View {
    @EnvironmentObject var backupManager: BackupManager
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var favoritesStore: FavoritesStore

    let entry: DefaultEntry

    @State private var editedValue: String = ""
    @State private var currentSystemValue: String = "…"
    @State private var valueBeforeEdit: String = ""   // for session change tracking
    @State private var isLoading = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showRestoreConfirm = false
    @State private var pendingRestartAction: RestartAction = .none
    @State private var needsFullDiskAccess = false
    @State private var statusToken = 0
    @State private var isBusy = false   // a write / backup / restore is running

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                headerSection
                Divider()
                systemValueSection
                Divider()

                if needsFullDiskAccess {
                    fullDiskAccessBanner
                } else if entry.type.isEditable {
                    editSection
                    Divider()
                } else {
                    Label("This type (\(entry.type.rawValue)) is read-only — arrays and dicts cannot be edited here.", systemImage: "lock")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Divider()
                }

                if entry.type.isEditable && !needsFullDiskAccess {
                    backupSection
                }

                if let msg = statusMessage {
                    Label(msg, systemImage: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(statusIsError ? .red : .green)
                        .font(.callout)
                        .transition(.opacity)
                }

                if pendingRestartAction != .none {
                    restartBanner
                }

                Spacer()
            }
            .padding(24)
        }
        .navigationTitle(entry.key)
        // ContentView gives this view a new identity per entry (.id), so all
        // @State starts fresh and onAppear runs again for every selection.
        .onAppear(perform: loadCurrentValue)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                TypeBadge(type: entry.type)
                Spacer()
                // Favorite toggle
                Button {
                    favoritesStore.toggle(entry)
                } label: {
                    Image(systemName: favoritesStore.isFavorite(entry) ? "star.fill" : "star")
                        .foregroundStyle(favoritesStore.isFavorite(entry) ? .yellow : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help(favoritesStore.isFavorite(entry) ? "Remove from Favorites" : "Add to Favorites")

                // Open in System Settings button
                if let settingsURL = SettingsURLResolver.url(for: entry) {
                    Button {
                        NSWorkspace.shared.open(settingsURL)
                    } label: {
                        Label("Open in Settings", systemImage: "gear")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open the related System Settings pane")
                }
                // Source links
                if let sources = entry.sources, !sources.isEmpty {
                    Menu {
                        ForEach(sources, id: \.self) { urlString in
                            if let url = URL(string: urlString) {
                                Link(destination: url) {
                                    Label(urlString, systemImage: "link")
                                }
                            }
                        }
                    } label: {
                        Label("\(sources.count) source\(sources.count == 1 ? "" : "s")", systemImage: "safari")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            Text(entry.key)
                .font(.title2.bold())
                .textSelection(.enabled)
            Text(entry.domain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            // Description
            if let desc = entry.description {
                Text(desc)
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.8))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Current System Value

    private var systemValueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Current System Value", systemImage: "desktopcomputer")
                .font(.headline)
            if isLoading {
                ProgressView()
            } else {
                HStack {
                    Text(currentSystemValue)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button("", systemImage: "arrow.clockwise") { loadCurrentValue() }
                        .buttonStyle(.borderless)
                        .help("Refresh")
                }
            }
        }
    }

    // MARK: - Edit Value

    private var editSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Edit Value", systemImage: "pencil")
                .font(.headline)

            // If macos-defaults.com documented specific allowed values, show them as a picker
            if let choices = entry.allValues, choices.count > 1 {
                valuePickerEditor(choices: choices)
            } else {
                switch entry.type {
                case .bool:   boolEditor
                case .integer: intEditor
                case .float:  floatEditor
                default:      stringEditor
                }
            }

            // Show documented default value
            HStack(spacing: 8) {
                Text("Documented default:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.value)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
                Button("Use default") { editedValue = entry.value }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            // CLI command preview
            cliCommandRow

            HStack {
                Button("Apply", systemImage: "checkmark.circle.fill") { applyValue() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Reset to Current") { loadCurrentValue() }
                    .buttonStyle(.bordered)
                if isBusy {
                    ProgressView().controlSize(.small)
                }
            }
            .disabled(isBusy || isLoading)
        }
    }

    // MARK: - CLI Command

    private var cliCommand: String {
        let value = (try? ApplyManager.normalisedValue(editedValue, for: entry.type)) ?? editedValue
        return ApplyManager.shellCommand(domain: entry.domain, key: entry.key, type: entry.type, value: value)
    }

    private var cliCommandRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Terminal command:")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(cliCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Button("", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cliCommand, forType: .string)
                }
                .buttonStyle(.borderless)
                .help("Copy command to clipboard")
            }
        }
    }

    // MARK: - Value editors

    private func valuePickerEditor(choices: [String]) -> some View {
        // If the system currently holds an undocumented value, offer it too —
        // otherwise nothing would appear selected and it could not be re-applied.
        let options = (valueBeforeEdit.isEmpty || choices.contains(valueBeforeEdit))
            ? choices : choices + [valueBeforeEdit]
        return VStack(alignment: .leading, spacing: 6) {
            Text("Value:")
                .font(.subheadline)
            ForEach(options, id: \.self) { v in
                HStack(spacing: 8) {
                    Image(systemName: editedValue == v ? "circle.inset.filled" : "circle")
                        .foregroundStyle(editedValue == v ? Color.accentColor : Color.secondary)
                    Text(v)
                        .font(.body)
                    if !choices.contains(v) {
                        Text("current, undocumented")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { editedValue = v }
            }
        }
    }

    private var boolEditor: some View {
        HStack(spacing: 16) {
            Text("Value:")
            Picker("", selection: $editedValue) {
                Text("true").tag("true")
                Text("false").tag("false")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
        }
    }

    private var intEditor: some View {
        HStack {
            Text("Value:")
            TextField("Integer", text: $editedValue)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .onChange(of: editedValue) { _, newValue in
                    // ASCII digits only, optional leading minus.
                    var filtered = String(newValue.filter { $0.isASCII && $0.isNumber })
                    if newValue.hasPrefix("-") { filtered = "-" + filtered }
                    if filtered != newValue { editedValue = filtered }
                }
        }
    }

    private var floatEditor: some View {
        HStack {
            Text("Value:")
            TextField("Float", text: $editedValue)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
        }
    }

    private var stringEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Value:")
            TextField("Value", text: $editedValue, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)
                .font(.body.monospaced())
        }
    }

    // MARK: - Backup / Restore

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Backup & Restore", systemImage: "shield")
                .font(.headline)

            if let backed = backupManager.backedUpValue(for: entry) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Backed-up value:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(backed)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(8)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Button("Backup Current Value", systemImage: "arrow.down.circle") {
                    isBusy = true
                    Task {
                        await backupManager.backup(entry: entry)
                        isBusy = false
                        setStatus("Backed up successfully.", isError: false)
                    }
                }
                .buttonStyle(.bordered)

                if backupManager.hasBackup(for: entry) {
                    Button("Restore", systemImage: "arrow.counterclockwise.circle", role: .destructive) {
                        showRestoreConfirm = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .disabled(isBusy)
        }
        .confirmationDialog("Restore \(entry.key)?", isPresented: $showRestoreConfirm) {
            Button("Restore", role: .destructive) { restoreValue() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let v = backupManager.backedUpValue(for: entry) {
                Text("Restore to: \(v)")
            }
        }
    }

    // MARK: - Full Disk Access Banner

    private var fullDiskAccessBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Disk Access required")
                        .font(.callout.bold())
                    Text("\(entry.domain) runs in a sandbox container. defaultsManager needs Full Disk Access to read or write its preferences.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Open Privacy & Security Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Restart Banner

    private var restartBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: bannerIcon)
                .foregroundStyle(bannerColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Restart required")
                    .font(.callout.bold())
                Text(bannerMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if case .killProcess(let name) = pendingRestartAction {
                Button("Restart \(name) Now") {
                    RestartActionResolver.perform(pendingRestartAction)
                    withAnimation { pendingRestartAction = .none }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Button("", systemImage: "xmark") {
                withAnimation { pendingRestartAction = .none }
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(12)
        .background(bannerColor.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(bannerColor.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var bannerIcon: String {
        if case .logout = pendingRestartAction { return "arrow.right.square" }
        return "exclamationmark.arrow.circlepath"
    }

    private var bannerColor: Color {
        if case .logout = pendingRestartAction { return .orange }
        return .blue
    }

    private var bannerMessage: String {
        switch pendingRestartAction {
        case .killProcess(let name): return "The change will take effect after \(name) restarts."
        case .logout:                return "Log out and log back in for this change to take effect."
        case .none:                  return ""
        }
    }

    // MARK: - Actions

    private func loadCurrentValue() {
        isLoading = true
        let domain = entry.domain
        let key = entry.key
        DispatchQueue.global(qos: .userInitiated).async {
            let containerised = ApplyManager.needsFullDiskAccess(for: domain)
            let val = containerised ? nil : ApplyManager.readCurrentValue(domain: domain, key: key)
            DispatchQueue.main.async {
                needsFullDiskAccess = containerised
                currentSystemValue = val ?? (containerised ? "(sandbox — needs Full Disk Access)" : "(not set)")
                let normalised = Self.normalise(val ?? entry.value, for: entry.type)
                editedValue = normalised
                valueBeforeEdit = normalised   // capture pre-edit value for session tracking
                isLoading = false
            }
        }
    }

    /// Normalises raw values from `defaults read` into the canonical form
    /// expected by `defaults write`. Booleans come back as "0"/"1" from the
    /// CLI but write only accepts "true"/"false"/"yes"/"no".
    private static func normalise(_ raw: String, for type: DefaultValueType) -> String {
        guard type == .bool else { return raw }
        return (try? ApplyManager.normalisedValue(raw, for: type)) ?? raw
    }

    /// Validates on the main thread, then backs up and writes in the background
    /// (each step spawns `/usr/bin/defaults`, which must not block the UI).
    private func applyValue() {
        let value: String
        do {
            // Validate first so an invalid value neither touches the backup nor the system.
            value = try ApplyManager.normalisedValue(editedValue, for: entry.type)
        } catch {
            setStatus(error.localizedDescription, isError: true)
            return
        }
        let entry = entry
        let before = valueBeforeEdit
        isBusy = true
        Task {
            defer { isBusy = false }
            // Keep the *original* value as backup — don't overwrite it on every apply.
            await backupManager.backupIfNeeded(entry: entry)
            do {
                try await Task.detached(priority: .userInitiated) {
                    try ApplyManager.write(domain: entry.domain, key: entry.key, value: value, type: entry.type)
                }.value
                setStatus("Applied successfully.", isError: false)
                sessionStore.record(entry: entry, oldValue: before, newValue: value)
                loadCurrentValue()
                let action = RestartActionResolver.action(for: entry)
                withAnimation { pendingRestartAction = action }
            } catch {
                setStatus(error.localizedDescription, isError: true)
            }
        }
    }

    private func restoreValue() {
        let entry = entry
        let before = valueBeforeEdit
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await backupManager.restore(entry: entry)
                let restored = await Task.detached(priority: .userInitiated) {
                    ApplyManager.readCurrentValue(domain: entry.domain, key: entry.key)
                }.value
                setStatus("Restored successfully.", isError: false)
                sessionStore.record(entry: entry, oldValue: before,
                                    newValue: Self.normalise(restored ?? entry.value, for: entry.type))
                loadCurrentValue()
                let action = RestartActionResolver.action(for: entry)
                withAnimation { pendingRestartAction = action }
            } catch {
                setStatus(error.localizedDescription, isError: true)
            }
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusToken += 1
        let token = statusToken
        withAnimation {
            statusMessage = message
            statusIsError = isError
        }
        // Only clear if no newer message replaced this one in the meantime.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard token == statusToken else { return }
            withAnimation { statusMessage = nil }
        }
    }
}
