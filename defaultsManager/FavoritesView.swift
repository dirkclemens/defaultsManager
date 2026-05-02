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
                            let script = favoritesStore.exportScript(for: favorites)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(script, forType: .string)
                            withAnimation { showCopiedFeedback = true }
                        }
                        Button("Save as Shell Script…", systemImage: "square.and.arrow.down") {
                            showExportPanel = true
                        }
                    } label: {
                        Label("Export Favorites", systemImage: "square.and.arrow.up")
                    }
                    .help("Export all favorites as shell defaults write commands")
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
            document: ShellScriptDocument(content: favoritesStore.exportScript(for: favorites)),
            contentType: .shellScript,
            defaultFilename: "macos-defaults-favorites"
        ) { _ in }
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
