//
//  FavoritesView.swift
//  defaultsManager
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FavoritesView: View {
    @EnvironmentObject var store: DefaultsStore
    @EnvironmentObject var favoritesStore: FavoritesStore
    @Binding var selectedEntry: DefaultEntry?

    @State private var showExportPanel = false
    @State private var showCopiedFeedback = false
    @State private var exportDocument = ShellScriptDocument(content: "")
    @State private var isBuildingScript = false

    private var favorites: [DefaultEntry] {
        favoritesStore.favorites(from: store.entries)
    }

    var body: some View {
        Group {
            if favorites.isEmpty {
                ContentUnavailableView(
                    "No Favorites",
                    systemImage: "star",
                    description: Text("Tap ⭐ in any setting's detail view to add it as a favorite.")
                )
            } else {
                List(favorites, selection: $selectedEntry) { entry in
                    EntryRow(entry: entry, showCategory: true)
                        .tag(entry)
                }
            }
        }
        .navigationTitle("Favorites")
        .navigationSubtitle(favorites.isEmpty ? "" :
            "\(favorites.count) favorite\(favorites.count == 1 ? "" : "s")")
        .toolbar {
            if !favorites.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Copy as Shell Script", systemImage: "terminal") {
                            Task {
                                let script = await buildScript()
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(script, forType: .string)
                                withAnimation { showCopiedFeedback = true }
                            }
                        }
                        Button("Save as Shell Script…", systemImage: "square.and.arrow.down") {
                            Task {
                                exportDocument = ShellScriptDocument(content: await buildScript())
                                showExportPanel = true
                            }
                        }
                    } label: {
                        Label("Export Favorites", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isBuildingScript)
                    .help("Export the current values of all favorites as defaults write commands")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showCopiedFeedback {
                Label("Script copied to clipboard", systemImage: "checkmark.circle.fill")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { showCopiedFeedback = false }
                        }
                    }
            }
        }
        .fileExporter(
            isPresented: $showExportPanel,
            document: exportDocument,
            contentType: .shellScript,
            defaultFilename: "macos-defaults-favorites"
        ) { _ in }
    }

    /// Reads the favorites' current values off the main thread, then renders the script.
    private func buildScript() async -> String {
        isBuildingScript = true
        defer { isBuildingScript = false }
        let entries = favorites
        let keys = entries.map { ($0.domain, $0.key) }
        let values = await Task.detached(priority: .userInitiated) {
            keys.map { ApplyManager.readCurrentValue(domain: $0.0, key: $0.1) }
        }.value
        return favoritesStore.exportScript(for: entries, currentValues: values)
    }
}

// MARK: - Shell Script File Document

struct ShellScriptDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.shellScript] }
    let content: String

    init(content: String) { self.content = content }

    init(configuration: ReadConfiguration) throws {
        content = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(content.utf8))
    }
}

extension UTType {
    static var shellScript: UTType { UTType(filenameExtension: "sh") ?? .plainText }
}
