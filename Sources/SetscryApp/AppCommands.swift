//
//  AppCommands.swift
//  Setscry
//
//  Created by Luis Resendez on 09/08/2026.
//

import SwiftUI

/// The menu bar.
///
/// Commands live outside the view hierarchy, which is why the models are owned
/// by the `App` and handed to both here and to the views.
struct AppCommands: Commands {
    let model: AppModel
    let semantic: SemanticModel

    /// Names the size in the menu item, so clearing the cache is an informed
    /// choice rather than a guess at what is about to be thrown away.
    private var clearCacheTitle: String {
        let bytes = semantic.cachedEmbeddingBytes
        guard bytes > 0 else { return "Clear cached image readings" }
        return "Clear cached image readings (\(bytes.formatted(.byteCount(style: .file))))"
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open folder…") { model.chooseFolder() }
                .keyboardShortcut("o")

            Menu("Open recent") {
                ForEach(model.recentFolders, id: \.self) { folder in
                    Button(folder.lastPathComponent) { model.open(folder: folder) }
                }

                if !model.recentFolders.isEmpty {
                    Divider()
                    Button("Clear menu") { model.clearRecentFolders() }
                }
            }
            .disabled(model.recentFolders.isEmpty)
        }

        CommandGroup(after: .saveItem) {
            Button("Export report…") { model.exportReport() }
                .keyboardShortcut("e")
                .disabled(model.analysis == nil)

            Divider()

            Button("Rescan folder") { model.rescan() }
                .keyboardShortcut("r")
                .disabled(model.analysis == nil)

            Button("Close folder") { model.close() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(model.analysis == nil)

            Divider()

            Button(clearCacheTitle) {
                Task { await semantic.clearCachedEmbeddings() }
            }
            .disabled(semantic.cachedEmbeddingBytes == 0)
        }

        CommandGroup(replacing: .help) {
            Button("Setscry help") {
                NotificationCenter.default.post(name: .showSetscryHelp, object: nil)
            }
            .keyboardShortcut("?", modifiers: .command)
        }

        CommandMenu("Go") {
            // ⌘1…⌘9, in the order the sidebar lists them. Sections past the
            // ninth are reachable from the sidebar only.
            ForEach(Array(DatasetSection.shortcutCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { model.selectedSection = section }
                    .keyboardShortcut(
                        KeyEquivalent(Character("\(index + 1)")),
                        modifiers: .command
                    )
                    .disabled(model.analysis == nil)
            }
        }
    }
}
