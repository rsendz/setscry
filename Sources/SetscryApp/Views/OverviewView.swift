//
//  OverviewView.swift
//  Setscry
//
//  Created by Luis Resendez on 11/08/2026.
//

import SwiftUI
import SetscryCore

struct OverviewView: View {
    let analysis: DatasetAnalysis

    @Environment(AppModel.self) private var model

    private var health: HealthReport { analysis.health }

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(columns: columns, spacing: 12) {
                    StatTile(
                        value: health.totalImages.formatted(),
                        title: "Images",
                        detail: "\(health.totalBytes.formatted(.byteCount(style: .file))) across \(health.formats.count) format\(health.formats.count == 1 ? "" : "s")",
                        systemImage: "photo"
                    )

                    StatTile(
                        value: health.redundantCopies.formatted(),
                        title: "Redundant copies",
                        detail: health.redundantCopies == 0
                            ? "No byte-identical duplicates."
                            : "Byte-identical. Removing them frees \(health.reclaimableBytes.formatted(.byteCount(style: .file))).",
                        systemImage: "doc.on.doc",
                        isConcerning: health.redundantCopies > 0,
                        destination: .exactDuplicates
                    )

                    StatTile(
                        value: health.nearDuplicateGroups.formatted(),
                        title: "Near-duplicate sets",
                        detail: health.nearDuplicateGroups == 0
                            ? "Nothing looked like a resized or re-encoded copy."
                            : "\(health.nearDuplicateImages.formatted()) images look like copies of each other.",
                        systemImage: "square.on.square.dashed",
                        isConcerning: health.nearDuplicateGroups > 0,
                        destination: .nearDuplicates
                    )

                    StatTile(
                        value: health.problemCount.formatted(),
                        title: "Won't open",
                        detail: health.problemCount == 0
                            ? "Every file opened successfully."
                            : "These files are empty, cut short or not really images.",
                        systemImage: "exclamationmark.triangle",
                        isConcerning: health.problemCount > 0,
                        destination: .problems
                    )

                    if health.hasSplits {
                        StatTile(
                            value: health.leakageCount.formatted(),
                            title: "Split leakage",
                            detail: health.leakageCount == 0
                                ? "No image appears in two splits."
                                : "The same image appears on both sides of a split.",
                            systemImage: "arrow.left.arrow.right",
                            isConcerning: health.leakageCount > 0,
                            destination: .leakage
                        )
                    }

                    if let imbalance = health.labelImbalance {
                        StatTile(
                            value: imbalance.formatted(.number.precision(.fractionLength(1))) + "×",
                            title: "Label imbalance",
                            detail: "The largest class has \(imbalance.formatted(.number.precision(.fractionLength(1))))× the images of the smallest.",
                            systemImage: "tag",
                            isConcerning: imbalance >= 3,
                            destination: .labels
                        )
                    }
                }

                breakdown("Formats", values: health.formats)

                if health.hasSplits {
                    breakdown("Splits", values: health.splits)
                }

                Text("Anything other than exact matches is a suggestion based on how similar two images look. Check before deleting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) { actionBar }
    }

    /// Pinned to the bottom, the same place every other section keeps its
    /// action, so it is in reach without scrolling to the end.
    private var actionBar: some View {
        HStack {
            Text("Scanned \(analysis.scannedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Export report…", systemImage: "square.and.arrow.up") { model.exportReport() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func breakdown(_ title: String, values: [CountedValue]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(values) { value in
                HStack {
                    Text(value.name)
                    Spacer()
                    Text(value.count.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
    }
}
