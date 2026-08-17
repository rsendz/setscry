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
        case .problems: "Won't Open"
        case .labels: "Folder Balance"
        case .leakage: "Split Leakage"
        case .search: "Search"
        case .clusters: "Clusters"
        case .labelCheck: "Label Check"
        }
    }

    /// One plain sentence per section, for the sidebar tooltip and the help
    /// sheet. Written for someone who has a folder of photos rather than a
    /// dataset: the precise term still appears in the view itself, but nobody
    /// should need to already know it to find their way around.
    var summary: String {
        switch self {
        case .overview: "The headline numbers for this folder, and a way into everything else."
        case .exactDuplicates: "The same file saved more than once. Identical down to the byte, so extra copies are safe to remove."
        case .nearDuplicates: "The same picture resized, re-saved or lightly edited. Worth a look before deleting."
        case .problems: "Files that won't open: empty, cut short, or not really images."
        case .labels: "How many images sit in each folder, so a lopsided set is obvious."
        case .leakage: "The same picture filed under more than one of train, validation and test — which quietly inflates how good a model looks."
        case .search: "Find images by describing them, instead of by filename."
        case .clusters: "Groups of images that look alike, which is how accidental themes show up."
        case .labelCheck: "Images that look more like a different folder's contents than their own."
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
