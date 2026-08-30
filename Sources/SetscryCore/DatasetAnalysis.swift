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

    /// Derived once in ``make(root:records:scannedAt:)`` rather than computed on
    /// demand. SwiftUI re-evaluates a view's `body` constantly, and a filter or
    /// a dictionary build in a computed property is then a full pass over every
    /// record per frame.
    public let problemImages: [ImageRecord]

    /// Positions in ``records``, not copies of them, so this costs a URL and an
    /// integer per file rather than a second copy of the dataset.
    private let indexByURL: [URL: Int]

    /// URLs taking part in each kind of finding, so asking about one file is a
    /// set lookup rather than a walk over every group.
    private let exactDuplicateURLs: Set<URL>
    private let nearDuplicateURLs: Set<URL>

    /// The record for a file, or `nil` when it is not in this folder.
    ///
    /// Views look records up by URL constantly: a cluster member, a search hit
    /// and a label suggestion all name one and none of them carry it.
    public func record(for url: URL) -> ImageRecord? {
        indexByURL[url].map { records[$0] }
    }

    public func hasExactDuplicates(_ record: ImageRecord) -> Bool {
        exactDuplicateURLs.contains(record.url)
    }

    public func hasNearDuplicates(_ record: ImageRecord) -> Bool {
        nearDuplicateURLs.contains(record.url)
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
            ),
            problemImages: records.filter { $0.problem != nil },
            indexByURL: Dictionary(
                records.enumerated().map { ($0.element.url, $0.offset) },
                uniquingKeysWith: { first, _ in first }
            ),
            exactDuplicateURLs: Set(exact.flatMap { $0.records.map(\.url) }),
            nearDuplicateURLs: Set(near.flatMap { $0.records.map(\.url) })
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
