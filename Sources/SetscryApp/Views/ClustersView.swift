//
//  ClustersView.swift
//  Setscry
//
//  Created by Luis Resendez on 11/08/2026.
//

import SwiftUI
import SetscryCore
import SetscryML

struct ClustersView: View {
    let analysis: DatasetAnalysis

    @Environment(SemanticModel.self) private var semantic

    private var recordsByURL: [URL: ImageRecord] {
        Dictionary(analysis.records.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        if !semantic.isReady {
            SemanticSetupView(
                analysis: analysis,
                title: "Group images by how they look",
                explanation: "Groups of images that look alike, which is how overrepresented subjects show up."
            )
        } else if semantic.clusters.isEmpty {
            ContentUnavailableView(
                "Not enough images to group",
                systemImage: "square.grid.3x3",
                description: Text("Grouping needs more images than this folder has.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("These groups are the model's opinion about what looks alike. They carry no labels; they are a way to notice structure you didn't expect.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(semantic.clusters) { cluster in
                        card(for: cluster)
                    }
                }
                .padding(20)
            }
        }
    }

    private func card(for cluster: EmbeddingClusterer.Cluster) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("^[\(cluster.members.count) image](inflect: true)")
                    .font(.headline)
                Spacer()
                Text(cohesionDescription(cluster.cohesion))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    // The most typical members first, so the row reads as a
                    // summary of the group rather than a random sample.
                    ForEach(cluster.members.prefix(12), id: \.self) { url in
                        if let record = recordsByURL[url] {
                            VStack(alignment: .leading, spacing: 4) {
                                ThumbnailView(record: record, side: 96)
                                    .imageActions(for: record)
                                Text(record.fileName)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(width: 96, alignment: .leading)
                            }
                        }
                    }

                    if cluster.members.count > 12 {
                        Text("+\(cluster.members.count - 12)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(height: 96)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }

    private func cohesionDescription(_ cohesion: Float) -> String {
        let quality = switch cohesion {
        case 0.9...: "very consistent"
        case 0.8..<0.9: "consistent"
        case 0.7..<0.8: "loose"
        default: "mixed"
        }
        return "\(quality) · \(cohesion.formatted(.number.precision(.fractionLength(2))))"
    }
}
