//
//  DatasetAnalysis.swift
//  Setscry
//
//  Created by Luis Resendez on 02/08/2026.
//

import Foundation

/// The complete result of scanning and analyzing one folder.
public struct DatasetAnalysis: Hashable, Sendable {
    public let root: URL
    public let scannedAt: Date
    public let records: [ImageRecord]
    public let exactDuplicates: [DuplicateGroup]
    public let nearDuplicates: [DuplicateGroup]
    public let leakage: [LeakageGroup]
    public let health: HealthReport

    public var problemImages: [ImageRecord] {
        records.filter { $0.problem != nil }
    }

    /// Runs every analysis over an already-scanned set of records.
    ///
    /// Kept separate from scanning so removing files can re-derive the findings
    /// without touching the disk again.
    public static func make(root: URL, records: [ImageRecord], scannedAt: Date = .now) -> DatasetAnalysis {
        let usable = records.filter(\.isUsable)
        let exact = DuplicateFinder.exactGroups(in: usable)
        let near = DuplicateFinder.nearGroups(in: usable)
        let leakage = LeakageFinder.groups(in: usable)

        return DatasetAnalysis(
            root: root,
            scannedAt: scannedAt,
            records: records,
            exactDuplicates: exact,
            nearDuplicates: near,
            leakage: leakage,
            health: HealthReport.make(
                records: records,
                exactDuplicates: exact,
                nearDuplicates: near,
                leakage: leakage
            )
        )
    }

    /// A copy of this analysis with the given files removed, recomputed from the
    /// remaining records.
    public func removing(_ removed: Set<URL>) -> DatasetAnalysis {
        DatasetAnalysis.make(
            root: root,
            records: records.filter { !removed.contains($0.url) },
            scannedAt: scannedAt
        )
    }
}
