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
    case allImages
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

    /// Only the first nine get their own shortcut. There is no ⌘10, and
    /// `Character("10")` traps at runtime rather than failing to compile.
    static var shortcutCases: [DatasetSection] { Array(allCases.prefix(9)) }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .allImages: "All images"
        case .exactDuplicates: "Exact duplicates"
        case .nearDuplicates: "Near duplicates"
        case .problems: "Won't open"
        case .labels: "Folder balance"
        case .leakage: "Split leakage"
        case .search: "Search"
        case .clusters: "Clusters"
        case .labelCheck: "Label check"
        }
    }

    /// One line per section, for the sidebar tooltip and the help sheet.
    /// Written for someone who has a folder of photos rather than a dataset.
    var summary: String {
        switch self {
        case .overview: "The numbers for this folder, and a way into the rest."
        case .allImages: "Every image in the folder, whether or not anything is wrong with it."
        case .exactDuplicates: "The same file saved twice. Identical down to the byte."
        case .nearDuplicates: "The same picture resized, re-saved or lightly edited."
        case .problems: "Files that won't open: empty, cut short, or not images."
        case .labels: "How many images are in each subfolder."
        case .leakage: "Images filed under more than one of train, validation and test."
        case .search: "Find images by describing them."
        case .clusters: "Groups of images that look alike."
        case .labelCheck: "Images that look more like another folder's contents."
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "chart.bar.doc.horizontal"
        case .allImages: "photo.on.rectangle.angled"
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
        case .overview, .allImages, .labels, .search, .clusters, .labelCheck: 0
        }
        return count > 0 ? count : nil
    }
}
