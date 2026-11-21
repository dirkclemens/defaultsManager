//
//  DefaultsStore.swift
//  defaultsManager
//

import Foundation
import Combine
import AppKit

class DefaultsStore: ObservableObject {
    @Published var entries: [DefaultEntry] = [] {
        didSet { entriesByCategory = Self.group(entries) }
    }
    @Published var categories: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Entries per category, pre-sorted by key. Rebuilt whenever `entries` changes
    /// so views don't filter + sort the full list on every render.
    private(set) var entriesByCategory: [String: [DefaultEntry]] = [:]

    init() {
        loadEntries()
    }

    // URL for the user-editable copy in Application Support
    nonisolated static var userFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("defaultsManager", isDirectory: true)
        return dir.appendingPathComponent("macos-defaults.json")
    }

    /// Copy of the bundle file as of the last merge — the common ancestor for
    /// the three-way merge in `mergeBundleEntries`.
    nonisolated static var bundleSnapshotURL: URL {
        userFileURL.deletingLastPathComponent().appendingPathComponent("macos-defaults.bundle-snapshot.json")
    }

    func loadEntries() {
        isLoading = true
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var decoded: [DefaultEntry] = []
            var loadError: String?
            do {
                let url = try Self.prepareUserFile()
                decoded = try JSONDecoder().decode([DefaultEntry].self, from: Data(contentsOf: url))
            } catch {
                loadError = "Failed to load \(Self.userFileURL.path):\n\(Self.describe(error))\n\nShowing the built-in settings instead. Fix the file and use Reload."
                // Fall back to the bundled list so the app stays usable.
                if let bundleURL = Bundle.main.url(forResource: "macos-defaults", withExtension: "json"),
                   let data = try? Data(contentsOf: bundleURL) {
                    decoded = (try? JSONDecoder().decode([DefaultEntry].self, from: data)) ?? []
                }
            }

            let cats = Array(Set(decoded.map(\.category))).sorted()

            DispatchQueue.main.async {
                guard let self else { return }
                self.entries = decoded
                self.categories = cats
                self.errorMessage = loadError
                self.isLoading = false
            }
        }
    }

    func entries(for category: String) -> [DefaultEntry] {
        entriesByCategory[category] ?? []
    }

    func entries(matching search: String) -> [DefaultEntry] {
        guard !search.isEmpty else { return [] }
        return entries.filter { matches($0, search: search) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    private func matches(_ entry: DefaultEntry, search: String) -> Bool {
        entry.key.localizedCaseInsensitiveContains(search) ||
        entry.domain.localizedCaseInsensitiveContains(search) ||
        entry.value.localizedCaseInsensitiveContains(search) ||
        entry.category.localizedCaseInsensitiveContains(search) ||
        (entry.description?.localizedCaseInsensitiveContains(search) ?? false)
    }

    private static func group(_ entries: [DefaultEntry]) -> [String: [DefaultEntry]] {
        Dictionary(grouping: entries, by: \.category).mapValues { $0.sorted { $0.key < $1.key } }
    }

    /// Reveals the user JSON file in Finder so the user can edit it.
    func revealUserFileInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Self.userFileURL])
    }

    /// Ensures a user-editable copy exists in Application Support.
    /// - On first launch: copies the bundle file.
    /// - On updates: three-way merges bundle changes without overwriting user edits.
    nonisolated private static func prepareUserFile() throws -> URL {
        let fm = FileManager.default
        let dest = userFileURL
        let dir = dest.deletingLastPathComponent()

        // Create ~/Library/Application Support/defaultsManager/ if needed
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let bundleURL = Bundle.main.url(forResource: "macos-defaults", withExtension: "json") else {
            throw NSError(domain: "DefaultsStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "macos-defaults.json not found in bundle"])
        }

        if !fm.fileExists(atPath: dest.path) {
            // First launch — just copy the bundle file
            try fm.copyItem(at: bundleURL, to: dest)
        } else {
            try mergeBundleEntries(bundleURL: bundleURL, userURL: dest)
        }
        // Remember what the bundle looked like for the next merge.
        try? Data(contentsOf: bundleURL).write(to: bundleSnapshotURL, options: .atomic)

        return dest
    }

    /// Three-way merge of bundle updates into the user file (identity = domain+key):
    /// - new bundle entries are added (unless the user deleted them earlier),
    /// - entries the user never touched receive bundle corrections,
    /// - entries removed from the bundle are dropped if the user never touched them,
    /// - anything the user edited or added is preserved untouched.
    /// Without a snapshot (first run after upgrading) only new entries are added.
    nonisolated private static func mergeBundleEntries(bundleURL: URL, userURL: URL) throws {
        let decoder = JSONDecoder()
        let bundleEntries = try decoder.decode([DefaultEntry].self, from: Data(contentsOf: bundleURL))
        var userEntries = try decoder.decode([DefaultEntry].self, from: Data(contentsOf: userURL))
        let snapshot: [String: DefaultEntry]? = (try? Data(contentsOf: bundleSnapshotURL))
            .flatMap { try? decoder.decode([DefaultEntry].self, from: $0) }
            .map { Dictionary($0.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

        let bundleByID = Dictionary(bundleEntries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = false

        if let snapshot {
            userEntries = userEntries.compactMap { user in
                guard let old = snapshot[user.id], old == user else { return user }  // user-edited or user-added
                let new = bundleByID[user.id]
                if new != user { changed = true }
                return new  // nil → removed from bundle
            }
        }

        let userIDs = Set(userEntries.map(\.id))
        let additions = bundleEntries.filter { entry in
            !userIDs.contains(entry.id) && snapshot?[entry.id] == nil
        }
        if !additions.isEmpty {
            userEntries.append(contentsOf: additions)
            changed = true
        }

        guard changed else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(userEntries).write(to: userURL, options: .atomic)
    }

    /// Makes JSON decoding errors readable (which entry / field is broken).
    nonisolated private static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return error.localizedDescription }
        func path(_ ctx: DecodingError.Context) -> String {
            ctx.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        }
        switch decodingError {
        case .dataCorrupted(let ctx):
            return "Invalid JSON: \(ctx.underlyingError?.localizedDescription ?? ctx.debugDescription)"
        case .keyNotFound(let key, let ctx):
            return "Missing field '\(key.stringValue)' at \(path(ctx))"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx):
            return "\(ctx.debugDescription) at \(path(ctx))"
        @unknown default:
            return error.localizedDescription
        }
    }
}
