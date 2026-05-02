//
//  SessionStore.swift
//  defaultsManager
//

import Foundation
import Combine

struct ChangeRecord: Identifiable {
    let id: String           // == entry.id (domain|key)
    let entry: DefaultEntry
    let oldValue: String
    var newValue: String
    var changedAt: Date
}

class SessionStore: ObservableObject {
    @Published private(set) var changes: [ChangeRecord] = []

    /// Records a successful write. If the entry was already changed this session,
    /// only the new value and timestamp are updated (old value is preserved from
    /// the first change so a full before/after comparison is always visible).
    func record(entry: DefaultEntry, oldValue: String, newValue: String) {
        if let idx = changes.firstIndex(where: { $0.id == entry.id }) {
            changes[idx].newValue = newValue
            changes[idx].changedAt = Date()
        } else {
            changes.append(ChangeRecord(id: entry.id, entry: entry,
                                        oldValue: oldValue, newValue: newValue,
                                        changedAt: Date()))
        }
    }

    func isChanged(_ entry: DefaultEntry) -> Bool {
        changes.contains { $0.id == entry.id }
    }

    func changeRecord(for entry: DefaultEntry) -> ChangeRecord? {
        changes.first { $0.id == entry.id }
    }
}
