//
//  BackupManager.swift
//  defaultsManager
//

import Foundation
import Combine

@MainActor
class BackupManager: ObservableObject {

    // MARK: - Per-entry backup (used by DetailView)
    @Published var backups: [BackupEntry] = []

    // MARK: - Domain-level backup metadata
    @Published var lastBackupDate: Date?
    @Published var backedUpDomains: [String] = []

    private let metaFileName   = "backup_meta.json"
    private let domainBackupDir = "domain_backup"

    // MARK: - URLs

    private var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("defaultsManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var domainBackupURL: URL {
        let dir = appSupportDir.appendingPathComponent(domainBackupDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var metaURL: URL {
        appSupportDir.appendingPathComponent(metaFileName)
    }

    // Legacy per-entry backup file (kept for DetailView)
    var perEntryBackupURL: URL {
        appSupportDir.appendingPathComponent("defaultsManager_backup.json")
    }

    init() {
        loadMeta()
        loadPerEntryBackups()
    }

    // MARK: - Domain export/import (Backup All / Restore All)

    /// Exports each domain to a .plist file using `defaults export`.
    /// Run this `nonisolated` from a background Task.
    nonisolated func exportDomains(_ domains: [String], to backupDir: URL) -> (exported: [String], errors: [String]) {
        var exported: [String] = []
        var errors: [String] = []

        for domain in domains {
            let destFile = backupDir.appendingPathComponent("\(domain).plist")
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            proc.arguments = ["export", domain, destFile.path]
            let errPipe = Pipe()
            proc.standardError = errPipe
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    exported.append(domain)
                } else {
                    let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    errors.append("\(domain): \(msg.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            } catch {
                errors.append("\(domain): \(error.localizedDescription)")
            }
        }
        return (exported, errors)
    }

    /// Imports each .plist in the backup directory using `defaults import`.
    /// Run this `nonisolated` from a background Task.
    nonisolated func importDomains(from backupDir: URL) -> (restored: [String], errors: [String]) {
        var restored: [String] = []
        var errors: [String] = []

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupDir, includingPropertiesForKeys: nil
        ) else {
            return ([], ["Could not read backup directory"])
        }

        let plists = files.filter { $0.pathExtension == "plist" }
        for file in plists {
            let domain = file.deletingPathExtension().lastPathComponent
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            proc.arguments = ["import", domain, file.path]
            let errPipe = Pipe()
            proc.standardError = errPipe
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    restored.append(domain)
                } else {
                    let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    errors.append("\(domain): \(msg.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            } catch {
                errors.append("\(domain): \(error.localizedDescription)")
            }
        }
        return (restored, errors)
    }

    /// Called on main actor after a successful export to update metadata.
    func recordBackup(exportedDomains: [String]) {
        backedUpDomains = exportedDomains.sorted()
        lastBackupDate = Date()
        saveMeta()
    }

    var hasFullBackup: Bool { !backedUpDomains.isEmpty }

    // MARK: - Per-entry backup (DetailView)

    func backup(entry: DefaultEntry) {
        let current = ApplyManager.readCurrentValue(domain: entry.domain, key: entry.key)
        let saved = BackupEntry(
            domain: entry.domain,
            key: entry.key,
            value: current ?? entry.value,
            type: entry.type,
            backedUpAt: Date()
        )
        backups.removeAll { $0.domain == entry.domain && $0.key == entry.key }
        backups.append(saved)
        savePerEntryBackups()
    }

    func restore(entry: DefaultEntry) throws {
        guard let saved = backups.first(where: { $0.domain == entry.domain && $0.key == entry.key }) else {
            throw BackupError.noBackupFound(entry.domain, entry.key)
        }
        try ApplyManager.write(domain: saved.domain, key: saved.key, value: saved.value, type: saved.type)
    }

    func hasBackup(for entry: DefaultEntry) -> Bool {
        backups.contains { $0.domain == entry.domain && $0.key == entry.key }
    }

    func backedUpValue(for entry: DefaultEntry) -> String? {
        backups.first { $0.domain == entry.domain && $0.key == entry.key }?.value
    }

    // MARK: - Persistence

    private func saveMeta() {
        struct Meta: Codable { var lastBackupDate: Date; var domains: [String] }
        let meta = Meta(lastBackupDate: lastBackupDate ?? Date(), domains: backedUpDomains)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metaURL, options: .atomic)
        }
    }

    private func loadMeta() {
        struct Meta: Codable { var lastBackupDate: Date; var domains: [String] }
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return }
        lastBackupDate = meta.lastBackupDate
        backedUpDomains = meta.domains
    }

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
