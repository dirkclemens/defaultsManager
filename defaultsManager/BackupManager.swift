//
//  BackupManager.swift
//  defaultsManager
//

import Foundation
import Combine

// MARK: - Full backup model

/// Metadata stored as `manifest.json` inside every full-backup folder.
nonisolated struct BackupManifest: Codable, Sendable {
    var createdAt: Date
    /// Domains that were exported successfully.
    var domains: [String]
    /// Keys managed by defaultsManager per domain at backup time. Restore only
    /// touches these. nil for backups migrated from versions before 1.0.2 —
    /// the keys currently in the parameter list are used for those.
    var keys: [String: [String]]?
}

/// One timestamped full backup: a folder with one `<domain>.plist` per domain
/// (the complete domain, kept as an archive) plus `manifest.json`.
nonisolated struct DomainBackup: Identifiable, Hashable, Sendable {
    let folder: URL
    let manifest: BackupManifest

    var id: URL { folder }
    var createdAt: Date { manifest.createdAt }

    func plistURL(for domain: String) -> URL {
        folder.appendingPathComponent("\(domain).plist")
    }

    static func == (a: DomainBackup, b: DomainBackup) -> Bool { a.folder == b.folder }
    func hash(into hasher: inout Hasher) { hasher.combine(folder) }
}

/// A managed key whose current system value differs from a full backup.
nonisolated struct RestoreChange: Identifiable, Hashable, Sendable {
    let domain: String
    let key: String
    let currentDisplay: String
    let backupDisplay: String
    /// Typed XML plist fragment to write; nil = key was not set in the backup → delete it.
    let backupFragment: String?

    /// Same format as `DefaultEntry.id`.
    var id: String { "\(domain)|\(key)" }
}

// MARK: - Backup manager

@MainActor
class BackupManager: ObservableObject {

    // MARK: Per-entry backup (used by DetailView)
    @Published var backups: [BackupEntry] = []

    // MARK: Full backups, newest first
    @Published private(set) var domainBackups: [DomainBackup] = []

    var hasFullBackup: Bool { !domainBackups.isEmpty }

    // MARK: - URLs

    nonisolated static var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("defaultsManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static var backupsRootURL: URL {
        let dir = appSupportDir.appendingPathComponent("domain_backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var perEntryBackupURL: URL {
        Self.appSupportDir.appendingPathComponent("defaultsManager_backup.json")
    }

    init() {
        Self.migrateLegacyBackup()
        loadPerEntryBackups()
        reloadDomainBackups()
    }

    // MARK: - Full backups

    func reloadDomainBackups() {
        domainBackups = Self.scanBackups()
    }

    /// Moves a backup folder to the Trash (recoverable).
    func trash(_ backup: DomainBackup) throws {
        try FileManager.default.trashItem(at: backup.folder, resultingItemURL: nil)
        reloadDomainBackups()
    }

    nonisolated private static func scanBackups() -> [DomainBackup] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: backupsRootURL, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                  let manifest = try? decoder.decode(BackupManifest.self, from: data) else { return nil }
            return DomainBackup(folder: dir, manifest: manifest)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// Exports every domain into a new timestamped folder. Earlier backups are kept.
    /// Blocking — call from a background task.
    nonisolated static func createBackup(keysByDomain: [String: [String]]) -> (backup: DomainBackup?, errors: [String]) {
        let fm = FileManager.default
        let now = Date()
        let folder = uniqueFolder(for: now)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return (nil, [error.localizedDescription])
        }

        var exported: [String] = []
        var errors: [String] = []
        for domain in keysByDomain.keys.sorted() {
            do {
                let dict = try ApplyManager.exportDomain(domain)
                let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
                try data.write(to: folder.appendingPathComponent("\(domain).plist"), options: .atomic)
                exported.append(domain)
            } catch {
                errors.append("\(domain): \(error.localizedDescription)")
            }
        }

        guard !exported.isEmpty else {
            try? fm.removeItem(at: folder)
            return (nil, errors)
        }

        let manifest = BackupManifest(createdAt: now, domains: exported,
                                      keys: keysByDomain.filter { exported.contains($0.key) })
        do {
            try writeManifest(manifest, to: folder)
        } catch {
            try? fm.removeItem(at: folder)
            return (nil, errors + ["manifest: \(error.localizedDescription)"])
        }
        return (DomainBackup(folder: folder, manifest: manifest), errors)
    }

    /// Lists every managed key whose live value differs from `backup`.
    /// Blocking — call from a background task.
    nonisolated static func differences(for backup: DomainBackup,
                                        fallbackKeys: [String: [String]]) -> (changes: [RestoreChange], errors: [String]) {
        var changes: [RestoreChange] = []
        var errors: [String] = []

        for domain in backup.manifest.domains {
            let keys = Set(backup.manifest.keys?[domain] ?? fallbackKeys[domain] ?? [])
            guard !keys.isEmpty else { continue }

            guard let data = try? Data(contentsOf: backup.plistURL(for: domain)),
                  let saved = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
            else {
                errors.append("\(domain): backup file missing or unreadable")
                continue
            }
            let current: [String: Any]
            do {
                current = try ApplyManager.exportDomain(domain)
            } catch {
                errors.append("\(domain): \(error.localizedDescription)")
                continue
            }

            for key in keys.sorted() {
                let old = saved[key]
                let now = current[key]
                switch (old, now) {
                case (nil, nil):
                    continue
                case let (old?, now?) where (old as AnyObject).isEqual(now):
                    continue
                default:
                    break
                }
                var fragment: String?
                if let old {
                    do { fragment = try ApplyManager.plistFragment(for: old) } catch {
                        errors.append("\(domain) \(key): \(error.localizedDescription)")
                        continue
                    }
                }
                changes.append(RestoreChange(domain: domain, key: key,
                                             currentDisplay: ApplyManager.displayString(for: now),
                                             backupDisplay: ApplyManager.displayString(for: old),
                                             backupFragment: fragment))
            }
        }
        return (changes, errors)
    }

    /// Writes (or deletes) each selected key individually — all other keys of
    /// the domain stay untouched, unlike `defaults import` which replaces the
    /// whole domain. Blocking — call from a background task.
    nonisolated static func apply(_ changes: [RestoreChange]) -> (applied: [RestoreChange], errors: [String]) {
        var applied: [RestoreChange] = []
        var errors: [String] = []
        for change in changes {
            do {
                if let fragment = change.backupFragment {
                    try ApplyManager.writePlistFragment(domain: change.domain, key: change.key, fragment: fragment)
                } else {
                    try ApplyManager.delete(domain: change.domain, key: change.key)
                }
                applied.append(change)
            } catch {
                errors.append("\(change.domain) \(change.key): \(error.localizedDescription)")
            }
        }
        return (applied, errors)
    }

    // MARK: Folder helpers

    nonisolated private static func folderName(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return fmt.string(from: date)
    }

    nonisolated private static func uniqueFolder(for date: Date, suffix: String = "") -> URL {
        let base = folderName(for: date) + suffix
        var url = backupsRootURL.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = backupsRootURL.appendingPathComponent("\(base)-\(n)", isDirectory: true)
            n += 1
        }
        return url
    }

    nonisolated private static func writeManifest(_ manifest: BackupManifest, to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
    }

    /// Converts the single backup of versions ≤ 1.0.1 (`domain_backup/` +
    /// `backup_meta.json`) into a timestamped backup so it stays restorable.
    nonisolated private static func migrateLegacyBackup() {
        let fm = FileManager.default
        let legacyDir = appSupportDir.appendingPathComponent("domain_backup", isDirectory: true)
        let metaURL = appSupportDir.appendingPathComponent("backup_meta.json")
        guard fm.fileExists(atPath: legacyDir.path) else { return }

        struct LegacyMeta: Codable { var lastBackupDate: Date; var domains: [String] }
        let meta = (try? Data(contentsOf: metaURL)).flatMap { try? JSONDecoder().decode(LegacyMeta.self, from: $0) }
        let plists = ((try? fm.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "plist" }

        guard !plists.isEmpty else {
            try? fm.removeItem(at: legacyDir)
            try? fm.removeItem(at: metaURL)
            return
        }

        let available = Set(plists.map { $0.deletingPathExtension().lastPathComponent })
        let domains = (meta?.domains ?? Array(available)).filter(available.contains).sorted()
        let created = meta?.lastBackupDate
            ?? ((try? fm.attributesOfItem(atPath: legacyDir.path))?[.modificationDate] as? Date)
            ?? Date()
        let folder = uniqueFolder(for: created, suffix: "_migrated")
        do {
            try fm.moveItem(at: legacyDir, to: folder)
            try writeManifest(BackupManifest(createdAt: created, domains: domains, keys: nil), to: folder)
            try? fm.removeItem(at: metaURL)
        } catch {
            // Leave the legacy files in place; migration is retried on next launch.
        }
    }

    // MARK: - Per-entry backup (DetailView)

    /// Saves the current system value of `entry`, replacing any earlier backup.
    /// The `defaults read` runs off the main thread.
    func backup(entry: DefaultEntry) async {
        let domain = entry.domain, key = entry.key
        let current = await Task.detached(priority: .userInitiated) {
            ApplyManager.readCurrentValue(domain: domain, key: key)
        }.value
        // `defaults read` prints booleans as 1/0, which `defaults write -bool` rejects.
        let value = current.map { (try? ApplyManager.normalisedValue($0, for: entry.type)) ?? $0 }
        let saved = BackupEntry(
            domain: entry.domain,
            key: entry.key,
            value: value ?? entry.value,
            type: entry.type,
            backedUpAt: Date(),
            wasSet: current != nil
        )
        backups.removeAll { $0.domain == entry.domain && $0.key == entry.key }
        backups.append(saved)
        savePerEntryBackups()
    }

    /// Backs up `entry` only if no backup exists yet, so repeated edits keep
    /// the original value instead of the previous edit.
    func backupIfNeeded(entry: DefaultEntry) async {
        guard !hasBackup(for: entry) else { return }
        await backup(entry: entry)
    }

    /// Restores the per-entry backup; the `defaults` calls run off the main thread.
    func restore(entry: DefaultEntry) async throws {
        guard let saved = backups.first(where: { $0.domain == entry.domain && $0.key == entry.key }) else {
            throw BackupError.noBackupFound(entry.domain, entry.key)
        }
        try await Task.detached(priority: .userInitiated) {
            if saved.wasSet == false {
                // Key did not exist before — remove it so macOS falls back to its built-in default.
                if ApplyManager.readCurrentValue(domain: saved.domain, key: saved.key) != nil {
                    try ApplyManager.delete(domain: saved.domain, key: saved.key)
                }
            } else {
                try ApplyManager.write(domain: saved.domain, key: saved.key, value: saved.value, type: saved.type)
            }
        }.value
    }

    func hasBackup(for entry: DefaultEntry) -> Bool {
        backups.contains { $0.domain == entry.domain && $0.key == entry.key }
    }

    func backedUpValue(for entry: DefaultEntry) -> String? {
        guard let saved = backups.first(where: { $0.domain == entry.domain && $0.key == entry.key }) else { return nil }
        return saved.wasSet == false ? "(not set)" : saved.value
    }

    // MARK: - Persistence

    private func savePerEntryBackups() {
        if let data = try? JSONEncoder().encode(backups) {
            try? data.write(to: perEntryBackupURL, options: .atomic)
        }
    }

    private func loadPerEntryBackups() {
        guard let data = try? Data(contentsOf: perEntryBackupURL),
              let decoded = try? JSONDecoder().decode([BackupEntry].self, from: data) else { return }
        backups = decoded
    }

    // MARK: - Error

    enum BackupError: LocalizedError {
        case noBackupFound(String, String)

        var errorDescription: String? {
            switch self {
            case .noBackupFound(let d, let k):
                return "No backup found for '\(k)' in domain '\(d)'."
            }
        }
    }
}
