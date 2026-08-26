//
//  ImageActions.swift
//  Setscry
//
//  Created by Luis Resendez on 12/08/2026.
//

import SwiftUI
import SetscryCore

/// The actions available on any image, wherever it appears.
///
/// One modifier rather than a menu per view: a right-click should offer the
/// same things in the duplicates list, a cluster and a search result, and
/// keeping them in one place is what makes that true.
struct ImageActions: ViewModifier {
    let record: ImageRecord
    /// Views with their own trash control suppress the one in the menu rather
    /// than offering it twice.
    var includesTrash = true

    @Environment(AppModel.self) private var model
    @Environment(SemanticModel.self) private var semantic

    func body(content: Content) -> some View {
        // A real button rather than a tap gesture: this makes the image
        // reachable by keyboard, gives VoiceOver something to announce, and
        // gets the pressed-state feedback a click target should have.
        Button { model.inspect(record) } label: {
            content
        }
            .buttonStyle(.plain)
            .accessibilityLabel("\(record.fileName), \(record.pixelSize?.displayString ?? "unknown size")")
            .accessibilityHint("Shows this image full size")
            // Dragging carries the file itself, so an image can go straight to
            // Finder or another app. Hold Command while dropping to move it
            // rather than copy it, the same as anywhere else in macOS.
            .draggable(record.url) {
                ThumbnailView(record: record, side: 96)
            }
            .contextMenu {
                Button("Get info", systemImage: "info.circle") { model.inspect(record) }
                Button("Quick Look", systemImage: "eye") { model.quickLook(record) }

                Divider()

                Button("Reveal in Finder", systemImage: "folder") { model.revealInFinder(record) }
                Button("Copy path", systemImage: "doc.on.clipboard") { model.copyPath(record) }

                if semantic.isReady {
                    Divider()
                    Button("Find similar images", systemImage: "square.on.square.dashed") {
                        semantic.findSimilar(to: record)
                        model.selectedSection = .search
                    }
                }

                if includesTrash {
                    Divider()
                    Button("Move to trash", systemImage: "trash", role: .destructive) {
                        Task { await model.moveToTrash([record]) }
                    }
                }
            }
            .help(record.relativePath)
    }
}

extension View {
    /// Adds the standard image actions: click to inspect, right-click for the rest.
    func imageActions(for record: ImageRecord, includesTrash: Bool = true) -> some View {
        modifier(ImageActions(record: record, includesTrash: includesTrash))
    }
}
