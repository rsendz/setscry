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
                "Every image opened",
                systemImage: "checkmark.circle",
                description: Text("Nothing in this folder is empty, cut short or corrupt.")
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
            .confirmationDialog(
                "Move ^[\(targets.count) file](inflect: true) to the Trash?",
                isPresented: $isConfirmingTrash,
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive) {
                    let doomed = targets
                    selection = []
                    Task { await model.moveToTrash(doomed) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("None of these files will open, so nothing is lost that an image viewer could have shown. They go to the Trash, so you can put them back.")
            }
        }
    }

    private var actionBar: some View {
        HStack {
            Text(selection.isEmpty
                 ? "^[\(records.count) file](inflect: true) that won't open. Select some, or trash them all."
                 : "^[\(selection.count) file](inflect: true) selected")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            if !selection.isEmpty {
                Button("Deselect All") { selection = [] }
            }

            Button(selection.isEmpty ? "Move All to Trash" : "Move Selected to Trash") {
                isConfirmingTrash = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

#Preview("Nothing broken") {
    ProblemImagesView(records: [])
        .environment(AppModel())
        .frame(width: 760, height: 520)
}
