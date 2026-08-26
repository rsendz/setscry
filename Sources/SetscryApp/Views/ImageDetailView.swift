//
//  ImageDetailView.swift
//  Setscry
//
//  Created by Luis Resendez on 12/08/2026.
//

import SwiftUI
import SetscryCore

/// A large look at one image, plus the facts behind it.
///
/// The app's whole job is helping someone decide whether two files really are
/// the same picture, or whether a label really is wrong. A grid of 128-pixel
/// thumbnails cannot answer either question, so every finding leads here.
struct ImageDetailView: View {
    let record: ImageRecord

    @Environment(AppModel.self) private var model
    @Environment(SemanticModel.self) private var semantic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            preview
            Divider()
            details
            Divider()
            // Outside the scroll view on purpose. These were previously the last
            // thing inside it, which put them off the bottom of the sheet with
            // nothing to suggest there was more to scroll to.
            actions
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 620, idealHeight: 780)
    }

    /// A fixed slice of the height rather than as much as it can take. Left
    /// greedy, the image squeezes the metadata below it down to a couple of
    /// rows, which is what made the buttons hard to find.
    private var preview: some View {
        ThumbnailView(record: record, side: 300)
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .background(.black.opacity(0.25))
    }

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.fileName)
                        .font(.headline)
                    Text(record.relativePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                let findings = model.findings(for: record)
                if !findings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(findings, id: \.self) { finding in
                            Label(finding, systemImage: "exclamationmark.circle")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    row("Dimensions", record.pixelSize?.displayString ?? "Unknown")
                    row("Size", record.byteSize.formatted(.byteCount(style: .file)))
                    row("Format", record.format ?? "Unknown")
                    if let label = record.label {
                        row("Label", label)
                    }
                    if let split = record.split {
                        row("Split", split.displayName)
                    }
                    if let modified = record.modifiedAt {
                        row("Modified", modified.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let hash = record.contentHash {
                        row("SHA-256", String(hash.prefix(16)) + "…")
                    }
                    if let perceptual = record.perceptualHash {
                        row("Perceptual hash", perceptual.hexString)
                    }
                }
                .font(.callout)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        HStack {
            Button("Reveal in Finder", systemImage: "folder") { model.revealInFinder(record) }
            Button("Quick Look", systemImage: "eye") { model.quickLook(record) }
            if semantic.isReady {
                Button("Find similar", systemImage: "square.on.square.dashed") {
                    semantic.findSimilar(to: record)
                    model.selectedSection = .search
                    dismiss()
                }
            }

            Spacer()

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private func row(_ name: String, _ value: String) -> some View {
        GridRow {
            Text(name)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .monospacedDigit()
        }
    }
}
