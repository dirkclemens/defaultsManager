//
//  DetailView.swift
//  defaultsManager
//

import SwiftUI
import Combine

struct DetailView: View {
    @EnvironmentObject var backupManager: BackupManager

    let entry: DefaultEntry

    @State private var editedValue: String = ""
    @State private var currentSystemValue: String = "…"
    @State private var isLoading = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showRestoreConfirm = false
    @State private var pendingRestartAction: RestartAction = .none

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                headerSection
                Divider()
                systemValueSection
                Divider()

                if entry.type.isEditable {
                    editSection
                    Divider()
                } else {
                    Label("This type (\(entry.type.rawValue)) is read-only — arrays and dicts cannot be edited here.", systemImage: "lock")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Divider()
                }

                backupSection

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
        .onAppear(perform: loadCurrentValue)
        .onChange(of: entry) { _, _ in
            pendingRestartAction = .none
            loadCurrentValue()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                TypeBadge(type: entry.type)
                Spacer()
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
                        Label("\(entry.sources!.count) source\(entry.sources!.count == 1 ? "" : "s")", systemImage: "safari")
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

            HStack {
                Button("Apply", systemImage: "checkmark.circle.fill") { applyValue() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Reset to Current") { loadCurrentValue() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Value editors

    private func valuePickerEditor(choices: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Value:")
                .font(.subheadline)
            ForEach(choices, id: \.self) { v in
                HStack(spacing: 8) {
                    Image(systemName: editedValue == v ? "circle.inset.filled" : "circle")
                        .foregroundStyle(editedValue == v ? Color.accentColor : Color.secondary)
                    Text(v)
                        .font(.body)
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
                .onReceive(editedValue.publisher.collect()) { chars in
                    let filtered = String(chars.filter { $0.isNumber || $0 == "-" })
                    if filtered != editedValue { editedValue = filtered }
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
                    backupManager.backup(entry: entry)
                    setStatus("Backed up successfully.", isError: false)
                }
                .buttonStyle(.bordered)

                if backupManager.hasBackup(for: entry) {
                    Button("Restore", systemImage: "arrow.counterclockwise.circle", role: .destructive) {
                        showRestoreConfirm = true
                    }
                    .buttonStyle(.bordered)
                }
            }
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
        statusMessage = nil
        editedValue = entry.value
        DispatchQueue.global(qos: .userInitiated).async {
            let val = ApplyManager.readCurrentValue(domain: entry.domain, key: entry.key)
            DispatchQueue.main.async {
                currentSystemValue = val ?? "(not set)"
                editedValue = Self.normalise(val ?? entry.value, for: entry.type)
                isLoading = false
            }
        }
    }

    /// Normalises raw values from `defaults read` into the canonical form
    /// expected by `defaults write`. Booleans come back as "0"/"1" from the
    /// CLI but write only accepts "true"/"false"/"yes"/"no".
    private static func normalise(_ raw: String, for type: DefaultValueType) -> String {
        guard type == .bool else { return raw }
        switch raw.lowercased() {
        case "1", "yes": return "true"
        case "0", "no":  return "false"
        default:         return raw
        }
    }

    private func applyValue() {
        backupManager.backup(entry: entry)
        do {
            try ApplyManager.write(domain: entry.domain, key: entry.key, value: editedValue, type: entry.type)
            setStatus("Applied successfully.", isError: false)
            loadCurrentValue()
            let action = RestartActionResolver.action(for: entry)
            withAnimation { pendingRestartAction = action }
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func restoreValue() {
        do {
            try backupManager.restore(entry: entry)
            setStatus("Restored successfully.", isError: false)
            loadCurrentValue()
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        withAnimation {
            statusMessage = message
            statusIsError = isError
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { statusMessage = nil }
        }
    }
}
