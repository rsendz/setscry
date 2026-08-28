//
//  ProblemImagesView.swift
//  Setscry
//
//  Created by Luis Resendez on 11/08/2026.
//

import SwiftUI
import SetscryCore

struct ProblemImagesView: View {
    let records: [ImageRecord]

    @Environment(AppModel.self) private var model
    @State private var selection: Set<URL> = []
    @State private var isConfirmingTrash = false

    /// What the Trash button acts on: the selection, or everything when nothing
    /// is selected. Selecting nothing is how most people arrive here, and
    /// "delete all the broken files" is the reason they came.
    private var targets: [ImageRecord] {
        selection.isEmpty ? records : records.filter { selection.contains($0.url) }
    }

    var body: some View {
        if records.isEmpty {
            ContentUnavailableView(
                "Everything opened",
                systemImage: "checkmark.circle",
                description: Text("Nothing here is empty, cut short or corrupt.")
            )
        } else {
            List(records, selection: $selection) { record in
                HStack(spacing: 12) {
                    ThumbnailView(record: record, side: 44)
                        .imageActions(for: record)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.relativePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(record.problem?.summary ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(record.byteSize.formatted(.byteCount(style: .file)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Button("Reveal in Finder", systemImage: "folder") { model.revealInFinder(record) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            // Pluralized by hand: a dialog title is handed to AppKit as plain
            // text, and inflection markup would be printed rather than applied.
            .confirmationDialog(
                "Move \(targets.count) file\(targets.count == 1 ? "" : "s") to the trash?",
                isPresented: $isConfirmingTrash,
                titleVisibility: .visible
            ) {
                Button("Move to trash", role: .destructive) {
                    let doomed = targets
                    selection = []
                    Task { await model.moveToTrash(doomed) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("None of these open, so there is nothing to lose. You can put them back from the trash.")
            }
        }
    }

    private var actionBar: some View {
        HStack {
            // Two separate Texts, not a ternary: a conditional produces a String,
            // and the inflection markup would then be printed rather than applied.
            Group {
                if selection.isEmpty {
                    Text("^[\(records.count) file](inflect: true) that won't open")
                } else {
                    Text("^[\(selection.count) file](inflect: true) selected")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()

            if !selection.isEmpty {
                Button("Deselect all") { selection = [] }
            }

            Button(selection.isEmpty ? "Move all to trash" : "Move selected to trash") {
                isConfirmingTrash = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        // More below than above, so the row does not sit against the window edge.
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(.bar)
    }
}

#Preview("Nothing broken") {
    ProblemImagesView(records: [])
        .environment(AppModel())
        .frame(width: 760, height: 520)
}
