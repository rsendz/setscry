//
//  SearchView.swift
//  Setscry
//
//  Created by Luis Resendez on 12/08/2026.
//

import SwiftUI
import SetscryCore

struct SearchView: View {
    let analysis: DatasetAnalysis

    @Environment(SemanticModel.self) private var semantic

    private var recordsByURL: [URL: ImageRecord] {
        Dictionary(analysis.records.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        if !semantic.isReady {
            SemanticSetupView(
                analysis: analysis,
                title: "Search by describing an image",
                explanation: "Setscry can read every image with a local model, then find them by description instead of by filename."
            )
        } else {
            @Bindable var semantic = semantic

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let subject = semantic.searchSubject {
                        subjectBanner(subject)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(semantic.searchResults) { match in
                            if let record = recordsByURL[match.url] {
                                resultTile(record: record, similarity: match.similarity)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .searchable(
                text: $semantic.searchText,
                placement: .toolbar,
                prompt: "a dog on a beach"
            )
            .onSubmit(of: .search) { semantic.search() }
            .overlay {
                if semantic.searchResults.isEmpty, semantic.searchSubject == nil {
                    emptyState
                }
            }
        }
    }

    /// Says what the results are being compared against when they came from an
    /// image rather than a typed description.
    private func subjectBanner(_ subject: ImageRecord) -> some View {
        HStack(spacing: 10) {
            ThumbnailView(record: subject, side: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Images similar to \(subject.fileName)")
                    .font(.headline)
                Text("Ranked by how close they are to this one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Clear", systemImage: "xmark.circle") { semantic.clearSearch() }
                .labelStyle(.titleOnly)
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private var emptyState: some View {
        if semantic.isSearching {
            ProgressView()
        } else if semantic.searchText.isEmpty {
            ContentUnavailableView(
                "Describe what you're looking for",
                systemImage: "magnifyingglass",
                description: Text("Try “a close-up of a face”, “something orange”, or “a screenshot”. Results are ranked by similarity, so the best matches come first.")
            )
        } else {
            ContentUnavailableView.search(text: semantic.searchText)
        }
    }

    private func resultTile(record: ImageRecord, similarity: Float) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(record: record, side: 140)
                .imageActions(for: record)

            Text(record.relativePath)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)

            // Shown as a raw similarity rather than a percentage: CLIP scores
            // are only meaningful relative to each other, and dressing one up
            // as a confidence would overstate it.
            Text("similarity \(similarity.formatted(.number.precision(.fractionLength(3))))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(width: 140, alignment: .leading)
    }
}
