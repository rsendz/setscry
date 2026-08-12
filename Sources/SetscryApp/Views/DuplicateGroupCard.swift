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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(group.records) { record in
                        member(record, isKeeper: record == group.keeper)
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.automatic)
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .confirmationDialog(
            "Move \(group.redundant.count) file\(group.redundant.count == 1 ? "" : "s") to the Trash?",
            isPresented: $isConfirmingTrash,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                Task { await model.moveToTrash(group.redundant) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(group.keeper?.relativePath ?? "The first file") is kept. The rest go to the Trash, so you can put them back.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("^[\(group.records.count) file](inflect: true)")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Keep First, Trash the Rest") { isConfirmingTrash = true }
                .disabled(group.redundant.isEmpty)
        }
    }

    private var subtitle: String {
        let reclaimable = group.reclaimableBytes.formatted(.byteCount(style: .file))
        return switch group.kind {
        case .exact:
            "Byte-identical · \(reclaimable) recoverable"
        case .near:
            "Similar to within \(group.spread ?? 0) of 64 bits · \(reclaimable) recoverable"
        }
    }

    private func member(_ record: ImageRecord, isKeeper: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(record: record, side: 128)
                .imageActions(for: record, includesTrash: false)
                .overlay(alignment: .topLeading) {
                    if isKeeper {
                        Text("Keep")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint, in: .capsule)
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }

            Text(record.relativePath)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)

            Text(details(for: record))
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Button("Reveal", systemImage: "folder") { model.revealInFinder(record) }
                Button("Trash", systemImage: "trash", role: .destructive) {
                    Task { await model.moveToTrash([record]) }
                }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .font(.callout)
        }
        .frame(width: 128, alignment: .leading)
    }

    private func details(for record: ImageRecord) -> String {
        [record.pixelSize?.displayString, record.byteSize.formatted(.byteCount(style: .file))]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
