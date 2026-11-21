//
//  KeyListView.swift
//  defaultsManager
//

import SwiftUI

struct KeyListView: View {
    @EnvironmentObject var store: DefaultsStore

    /// nil while showing global search results.
    let category: String?
    @Binding var selectedEntry: DefaultEntry?
    /// Owned by ContentView (search field in the sidebar).
    let searchText: String

    private var isGlobalSearch: Bool { !searchText.isEmpty || category == nil }

    private var filtered: [DefaultEntry] {
        if isGlobalSearch { return store.entries(matching: searchText) }
        return store.entries(for: category ?? "")
    }

    private var totalCount: Int {
        isGlobalSearch ? store.entries.count : store.entries(for: category ?? "").count
    }

    var body: some View {
        Group {
            if isGlobalSearch && filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(filtered, selection: $selectedEntry) { entry in
                    EntryRow(entry: entry, showCategory: isGlobalSearch)
                        .tag(entry)
                }
            }
        }
        .navigationTitle(isGlobalSearch ? "Search Results" : (category ?? ""))
        .navigationSubtitle("\(filtered.count) of \(totalCount) settings")
    }
}

struct EntryRow: View {
    @EnvironmentObject var backupManager: BackupManager
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var favoritesStore: FavoritesStore
    let entry: DefaultEntry
    var showCategory: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.key)
                        .font(.body)
                        .lineLimit(1)
                    if showCategory {
                        CategoryBadge(category: entry.category)
                    }
                    if sessionStore.isChanged(entry) {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(.orange)
                            .imageScale(.small)
                            .help("Changed this session")
                    }
                    if favoritesStore.isFavorite(entry) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .imageScale(.small)
                            .help("Favorite")
                    }
                }
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
