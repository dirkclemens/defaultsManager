//
//  ChangedView.swift
//  defaultsManager
//

import SwiftUI

struct ChangedView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @Binding var selectedEntry: DefaultEntry?

    var body: some View {
        Group {
            if sessionStore.changes.isEmpty {
                ContentUnavailableView(
                    "No Changes Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Settings you apply during this session will appear here.")
                )
            } else {
                List(sessionStore.changes, selection: $selectedEntry) { record in
                    ChangedRow(record: record)
                        .tag(record.entry)
                }
            }
        }
        .navigationTitle("Changed This Session")
        .navigationSubtitle(sessionStore.changes.isEmpty ? "" :
            "\(sessionStore.changes.count) setting\(sessionStore.changes.count == 1 ? "" : "s") changed")
    }
}

struct ChangedRow: View {
    let record: ChangeRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.entry.key)
                        .font(.body)
                        .lineLimit(1)
                    CategoryBadge(category: record.entry.category, color: .orange)
                }
                Text(record.entry.domain)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(record.oldValue)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .strikethrough()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(record.newValue)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                }
            }
            Spacer()
            TypeBadge(type: record.entry.type)
        }
        .padding(.vertical, 2)
    }
}

/// Small pill-shaped category label.
struct CategoryBadge: View {
    let category: String
    var color: Color = .accentColor

    var body: some View {
        Text(category)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
