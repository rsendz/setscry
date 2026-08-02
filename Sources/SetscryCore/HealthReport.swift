//
//  HealthReport.swift
//  Setscry
//
//  Created by Luis Resendez on 02/08/2026.
//

import Foundation

/// A handful of individually meaningful numbers about a dataset.
///
/// Deliberately not a single "quality score": every value here means one
/// concrete thing the user can act on.
public struct HealthReport: Hashable, Sendable {
    public let totalImages: Int
    public let totalBytes: Int64

    public let problemCount: Int

    public let exactDuplicateGroups: Int
    public let redundantCopies: Int
    public let reclaimableBytes: Int64

    public let nearDuplicateGroups: Int
    public let nearDuplicateImages: Int

    public let leakageCount: Int

    public let formats: [CountedValue]
    public let labels: [CountedValue]
    public let splits: [CountedValue]
    public let unlabeledCount: Int

    /// Ratio between the largest and smallest label; `nil` when there are fewer
    /// than two labels to compare.
    public var labelImbalance: Double? {
        guard labels.count >= 2,
              let largest = labels.first?.count,
              let smallest = labels.last?.count,
              smallest > 0 else { return nil }
        return Double(largest) / Double(smallest)
    }

    public var hasLabels: Bool { labels.count >= 2 }

    public var hasSplits: Bool { splits.count >= 2 }

    static func make(
        records: [ImageRecord],
        exactDuplicates: [DuplicateGroup],
        nearDuplicates: [DuplicateGroup],
        leakage: [LeakageGroup]
    ) -> HealthReport {
        let labeled = records.filter { $0.label != nil }

        return HealthReport(
            totalImages: records.count,
            totalBytes: records.reduce(0) { $0 + $1.byteSize },
            problemCount: records.filter { $0.problem != nil }.count,
            exactDuplicateGroups: exactDuplicates.count,
            redundantCopies: exactDuplicates.reduce(0) { $0 + $1.redundant.count },
            reclaimableBytes: exactDuplicates.reduce(0) { $0 + $1.reclaimableBytes },
            nearDuplicateGroups: nearDuplicates.count,
            nearDuplicateImages: nearDuplicates.reduce(0) { $0 + $1.records.count },
            leakageCount: leakage.count,
            formats: CountedValue.tally(records.map(\.format), unknownName: "Unknown"),
            labels: CountedValue.tally(labeled.map(\.label), unknownName: "Unlabeled"),
            splits: CountedValue.tally(
                records.map { $0.split?.displayName },
                unknownName: "Unsplit"
            ),
            unlabeledCount: records.count - labeled.count
        )
    }
}
