//
//  DatasetSection.swift
//  Setscry
//
//  Created by Luis Resendez on 09/08/2026.
//

import Foundation
import SetscryCore

/// The focused views a loaded dataset is split into, rather than one
/// overwhelming table.
enum DatasetSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case exactDuplicates
    case nearDuplicates
    case problems
    case labels
    case leakage
    case search
    case clusters
    case labelCheck

    var id: String { rawValue }

    /// Sections that need the CLIP model, grouped separately in the sidebar so
    /// it is obvious which findings are deterministic and which are the
    /// model's opinion.
    var needsModel: Bool {
        switch self {
        case .search, .clusters, .labelCheck: true
        default: false
        }
    }

    static var deterministicCases: [DatasetSection] {
        allCases.filter { !$0.needsModel }
    }

    static var modelCases: [DatasetSection] {
        allCases.filter(\.needsModel)
    }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .exactDuplicates: "Exact Duplicates"
        case .nearDuplicates: "Near Duplicates"
        case .problems: "Unreadable"
        case .labels: "Labels"
        case .leakage: "Split Leakage"
        case .search: "Search"
        case .clusters: "Clusters"
        case .labelCheck: "Label Check"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "chart.bar.doc.horizontal"
        case .exactDuplicates: "doc.on.doc"
        case .nearDuplicates: "square.on.square.dashed"
        case .problems: "exclamationmark.triangle"
        case .labels: "tag"
        case .leakage: "arrow.left.arrow.right"
        case .search: "magnifyingglass"
        case .clusters: "square.grid.3x3"
        case .labelCheck: "checkmark.seal"
        }
    }

    /// The count shown next to the section, or `nil` when there is nothing to flag.
    func badge(for analysis: DatasetAnalysis) -> Int? {
        let count = switch self {
        case .exactDuplicates: analysis.exactDuplicates.count
        case .nearDuplicates: analysis.nearDuplicates.count
        case .problems: analysis.health.problemCount
        case .leakage: analysis.leakage.count
        case .overview, .labels, .search, .clusters, .labelCheck: 0
        }
        return count > 0 ? count : nil
    }
}
