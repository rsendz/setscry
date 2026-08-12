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

    var body: some View {
        if records.isEmpty {
            ContentUnavailableView(
                "Every file decoded",
                systemImage: "checkmark.circle",
                description: Text("No empty, truncated or corrupt images in this folder.")
            )
        } else {
            List(records) { record in
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
        }
    }
}

#Preview("Nothing broken") {
    ProblemImagesView(records: [])
        .environment(AppModel())
        .frame(width: 760, height: 520)
}
