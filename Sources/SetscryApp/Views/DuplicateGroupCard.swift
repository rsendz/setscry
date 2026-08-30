//
//  DuplicateGroupCard.swift
//  Setscry
//
//  Created by Luis Resendez on 11/08/2026.
//

import SwiftUI
import SetscryCore

struct DuplicateGroupCard: View {
    let group: DuplicateGroup

    @Environment(AppModel.self) private var model
    @State private var isConfirmingTrash = false
    @State private var isDropTargeted = false

    var body: some View {
        // Resolved once per render rather than per tile. `member(_:)` used to
        // ask the model which record is the keeper for every thumbnail in the
        // group, each answer costing a scan of the group plus a whole-struct
        // comparison.
        card(keeper: model.keeper(of: group), redundant: model.redundant(in: group))
    }

    private func card(keeper: ImageRecord?, redundant: [ImageRecord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(redundant: redundant)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(group.records) { record in
                        member(record, keeper: keeper)
                    }
                }
                // Room for the overlay scrollbar to sit over nothing. It fades
                // in on top of the content, and anything under it cannot be
                // clicked until it fades out again.
                .padding(.bottom, 18)
            }
            .scrollIndicators(.automatic)

            keepWell
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .confirmationDialog(
            "Move \(redundant.count) file\(redundant.count == 1 ? "" : "s") to the trash?",
            isPresented: $isConfirmingTrash,
            titleVisibility: .visible
        ) {
            Button("Move to trash", role: .destructive) {
                Task { await model.moveToTrash(redundant) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(keeper?.relativePath ?? "The first file") stays. You can put the rest back from the trash.")
        }
    }

    private func header(redundant: [ImageRecord]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("^[\(group.records.count) file](inflect: true)")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Trash the rest") { isConfirmingTrash = true }
                .disabled(redundant.isEmpty)
        }
    }

    /// Drop any image from the group here to keep that one instead.
    ///
    /// The same choice is on every tile as a button; this is for the person who
    /// reaches for a drag, and it gives the drag somewhere to land inside the
    /// app rather than only out to Finder.
    private var keepWell: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.draw")
            Text("Drag an image here to keep that one")
        }
        .font(.caption)
        .foregroundStyle(isDropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        }
        .dropDestination(for: URL.self) { urls, _ in
            // Only images from this group: a drop from anywhere else has no
            // meaning here, and silently accepting it would be a lie.
            guard let match = group.records.first(where: { record in urls.contains(record.url) }) else {
                return false
            }
            model.chooseKeeper(match, in: group)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .animation(.easeOut(duration: 0.12), value: isDropTargeted)
    }

    private var subtitle: String {
        let reclaimable = group.reclaimableBytes.formatted(.byteCount(style: .file))
        return switch group.kind {
        case .exact:
            "Identical files, \(reclaimable) recoverable"
        case .near:
            "Similar to within \(group.spread ?? 0) of 64 bits, \(reclaimable) recoverable"
        }
    }

    private func member(_ record: ImageRecord, keeper: ImageRecord?) -> some View {
        let isKeeper = record == keeper

        return VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(record: record, side: 128)
                .imageActions(for: record)
                .overlay(alignment: .topLeading) {
                    if isKeeper {
                        Text("Keeping")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint, in: .capsule)
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.tint, lineWidth: isKeeper ? 2 : 0)
                }

            // Directly under the image rather than at the foot of the tile: at
            // the foot, the horizontal scrollbar covers it while it is fading,
            // so the button cannot be clicked just after a scroll.
            if isKeeper {
                Text("Kept")
                    .font(.caption2)
                    .foregroundStyle(.tint)
            } else {
                Button("Keep this one") { model.chooseKeeper(record, in: group) }
                    .buttonStyle(.borderless)
                    .font(.caption2)
            }

            Text(record.relativePath)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)

            Text(details(for: record))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 128, alignment: .leading)
    }

    private func details(for record: ImageRecord) -> String {
        [record.pixelSize?.displayString, record.byteSize.formatted(.byteCount(style: .file))]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
