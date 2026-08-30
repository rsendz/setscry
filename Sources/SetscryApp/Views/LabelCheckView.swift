//
//  LabelCheckView.swift
//  Setscry
//
//  Created by Luis Resendez on 11/08/2026.
//

import SwiftUI
import SetscryCore
import SetscryML

struct LabelCheckView: View {
    let analysis: DatasetAnalysis

    @Environment(SemanticModel.self) private var semantic
    @Environment(AppModel.self) private var model

    var body: some View {
        if !analysis.health.hasLabels {
            ContentUnavailableView {
                Label("No labels to check", systemImage: "tag")
            } description: {
                Text("Setscry reads labels from folder names. This folder doesn't have at least two labelled classes to compare.")
            }
        } else if !semantic.isReady {
            SemanticSetupView(
                analysis: analysis,
                title: "Check labels against the images",
                explanation: "Setscry can compare every image to the other images sharing its label, and point out the ones that look out of place."
            )
        } else if semantic.labelSuggestions.isEmpty {
            ContentUnavailableView(
                "Nothing looks out of place",
                systemImage: "checkmark.circle",
                description: Text("Every image sits closer to its own label than to any other.")
            )
        } else {
            List {
                Section {
                    ForEach(semantic.labelSuggestions) { suggestion in
                        row(for: suggestion)
                    }
                } header: {
                    // Automatic grammar agreement, so a single finding does not
                    // read "1 images".
                    Text("^[\(semantic.labelSuggestions.count) image](inflect: true) look more like another label. A prompt to look, not a verdict: an unusual but correctly labelled image lands here too.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                        .padding(.bottom, 6)
                }
            }
        }
    }

    private func row(for suggestion: LabelSanityChecker.Suggestion) -> some View {
        HStack(spacing: 12) {
            if let record = analysis.record(for: suggestion.url) {
                ThumbnailView(record: record, side: 56)
                    .imageActions(for: record)

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.relativePath)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("Filed under \(suggestion.currentLabel), but looks more like \(suggestion.suggestedLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("+\(suggestion.margin.formatted(.number.precision(.fractionLength(3))))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.orange)

                Button("Reveal in Finder", systemImage: "folder") {
                    model.revealInFinder(record)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}
