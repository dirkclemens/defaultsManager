//
//  KeyListView.swift
//  defaultsManager
//

import SwiftUI

struct KeyListView: View {
    @EnvironmentObject var store: DefaultsStore
    @EnvironmentObject var backupManager: BackupManager

    let category: String
    @Binding var selectedEntry: DefaultEntry?
    @Binding var searchText: String

    private var filtered: [DefaultEntry] {
        store.entries(for: category, matching: searchText)
    }

    var body: some View {
        List(filtered, selection: $selectedEntry) { entry in
            EntryRow(entry: entry)
                .tag(entry)
        }
        .searchable(text: $searchText, prompt: "Filter settings…")
        .navigationTitle(category)
        .navigationSubtitle("\(filtered.count) of \(store.entries(for: category).count) settings")
        .onChange(of: category) { _, _ in
            selectedEntry = nil
            searchText = ""
        }
    }
}

struct EntryRow: View {
    @EnvironmentObject var backupManager: BackupManager
    let entry: DefaultEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.key)
                    .font(.body)
                    .lineLimit(1)
                Text(entry.domain)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text(entry.value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                TypeBadge(type: entry.type)
                if backupManager.hasBackup(for: entry) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                        .imageScale(.small)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct TypeBadge: View {
    let type: DefaultValueType

    var body: some View {
        Text(type.rawValue)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch type {
        case .string: return .blue
        case .integer: return .purple
        case .float: return .orange
        case .bool: return .green
        case .array: return .cyan
        case .dict: return .indigo
        case .data: return .gray
        }
    }
}
