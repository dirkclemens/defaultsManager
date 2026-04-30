//
//  DefaultsStore.swift
//  defaultsManager
//

import Foundation
import Combine
import AppKit

// Ordered category list (macos-defaults.com chapters first, then additional)
let orderedCategories = [
    "Dock", "Screenshots", "Safari", "Finder", "Desktop",
    "Menu Bar", "Mouse", "Trackpad", "Keyboard", "Mission Control",
    "Feedback Assistant", "Xcode", "Simulator", "TextEdit",
    "Time Machine", "Activity Monitor", "Messages", "Miscellaneous",
    // Additional categories from supplementary defaults list
    "General", "Input", "Screen", "Mail", "iTunes",
    // New categories from community sources
    "Window Manager", "App Store",
]

class DefaultsStore: ObservableObject {
    @Published var entries: [DefaultEntry] = []
    @Published var categories: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    init() {
        loadEntries()
    }

    // URL for the user-editable copy in Application Support
    static var userFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("defaultsManager", isDirectory: true)
        return dir.appendingPathComponent("macos-defaults.json")
    }

    func loadEntries() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let url = try self.prepareUserFile()
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode([DefaultEntry].self, from: data)

                // Collect known categories plus any custom ones from the user file
                var seen = Set<String>()
                var cats: [String] = []
                for cat in decoded.map(\.category) where !seen.contains(cat) {
                    cats.append(cat)
                    seen.insert(cat)
                }
                cats.sort()

                DispatchQueue.main.async {
                    self.entries = decoded
                    self.categories = cats
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load macos-defaults.json: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    func entries(for category: String) -> [DefaultEntry] {
        entries.filter { $0.category == category }.sorted { $0.key < $1.key }
    }

    func entries(for category: String, matching search: String) -> [DefaultEntry] {
        let base = entries(for: category)
        if search.isEmpty { return base }
        return base.filter {
            $0.key.localizedCaseInsensitiveContains(search) ||
            $0.value.localizedCaseInsensitiveContains(search) ||
            $0.domain.localizedCaseInsensitiveContains(search)
        }
    }

    /// Reveals the user JSON file in Finder so the user can edit it.
    func revealUserFileInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Self.userFileURL])
    }

    /// Ensures a user-editable copy exists in Application Support.
    /// - On first launch: copies the bundle file.
    /// - On updates: merges new bundle entries (by domain+key) without overwriting user entries.
    private func prepareUserFile() throws -> URL {
        let fm = FileManager.default
        let dest = Self.userFileURL
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
            // Subsequent launches — merge any new entries from the bundle into the user file
            try mergeNewBundleEntries(bundleURL: bundleURL, userURL: dest)
        }

        return dest
    }

    /// Adds entries that exist in the bundle but not yet in the user file (identified by domain+key).
    /// User-added or user-modified entries are preserved untouched.
    private func mergeNewBundleEntries(bundleURL: URL, userURL: URL) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let bundleData = try Data(contentsOf: bundleURL)
        let userData = try Data(contentsOf: userURL)

        let bundleEntries = try decoder.decode([DefaultEntry].self, from: bundleData)
        var userEntries = try decoder.decode([DefaultEntry].self, from: userData)

        let userKeys = Set(userEntries.map { "\($0.domain)|\($0.key)" })
        let newEntries = bundleEntries.filter { !userKeys.contains("\($0.domain)|\($0.key)") }

        guard !newEntries.isEmpty else { return }

        userEntries.append(contentsOf: newEntries)
        let merged = try encoder.encode(userEntries)
        try merged.write(to: userURL, options: .atomic)
    }
}
