//
//  LeakageGroup.swift
//  Setscry
//
//  Created by Luis Resendez on 04/08/2026.
//

import Foundation

/// One image that appears in more than one split.
///
/// This is the finding most likely to change what a user does next: a test image
/// that also sits in the training set quietly inflates reported accuracy.
///
/// Modelled as a group rather than a pair on purpose. When a file has been copied
/// three times across two splits, that is still one leaked image, and saying so
/// once is more useful than listing every pairing.
public struct LeakageGroup: Identifiable, Hashable, Sendable {
    public let id: String
    /// Every copy of the image, ordered by split then path.
    public let records: [ImageRecord]
    /// The splits this image appears in, in train/validation/test order.
    public let splits: [DatasetSplit]
    /// True when at least two copies in different splits are byte-identical —
    /// a certainty rather than a suggestion.
    public let containsIdenticalFiles: Bool
    /// The widest perceptual gap within the group, in bits out of 64.
    public let spread: Int

    public init(records: [ImageRecord], containsIdenticalFiles: Bool, spread: Int) {
        let ordered = records.sorted { a, b in
            let orderA = a.split.map { DatasetSplit.allCases.firstIndex(of: $0) ?? 0 } ?? 0
            let orderB = b.split.map { DatasetSplit.allCases.firstIndex(of: $0) ?? 0 } ?? 0
            return orderA == orderB
                ? a.relativePath.localizedStandardCompare(b.relativePath) == .orderedAscending
                : orderA < orderB
        }

        self.id = ordered.map(\.relativePath).joined(separator: "|")
        self.records = ordered
        self.splits = DatasetSplit.allCases.filter { split in
            ordered.contains { $0.split == split }
        }
        self.containsIdenticalFiles = containsIdenticalFiles
        self.spread = spread
    }

    public var splitSummary: String {
        splits.map(\.displayName).joined(separator: " ↔ ")
    }

    /// Copies grouped under the split they belong to, for side-by-side display.
    public var recordsBySplit: [(split: DatasetSplit, records: [ImageRecord])] {
        splits.map { split in
            (split, records.filter { $0.split == split })
        }
    }
}
