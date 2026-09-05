//
//  LeakageFinder.swift
//  Setscry
//
//  Created by Luis Resendez on 04/08/2026.
//

import Foundation

/// Detects images that appear in more than one split.
public enum LeakageFinder {
    /// Runs over every usable record rather than one representative per
    /// duplicate family: an identical file copied into both `train` and `test`
    /// is the single most important case here, and collapsing duplicates first
    /// would hide exactly that.
    public static func groups(
        in records: [ImageRecord],
        threshold: Int = DuplicateFinder.defaultNearThreshold
    ) -> [LeakageGroup] {
        let splitRecords = records.filter { $0.split != nil }
        guard splitRecords.count > 1 else { return [] }

        return SimilarityClusterer.clusters(of: splitRecords, threshold: threshold)
            .filter { cluster in Set(cluster.compactMap(\.split)).count > 1 }
            .map { cluster in
                LeakageGroup(
                    records: cluster,
                    containsIdenticalFiles: hasIdenticalPairAcrossSplits(cluster),
                    spread: SimilarityClusterer.spread(of: cluster)
                )
            }
            .sorted {
                // Certainties first, then the closest matches.
                if $0.containsIdenticalFiles != $1.containsIdenticalFiles {
                    return $0.containsIdenticalFiles
                }
                return $0.spread < $1.spread
            }
    }

    private static func hasIdenticalPairAcrossSplits(_ cluster: [ImageRecord]) -> Bool {
        var splitsByHash: [String: Set<DatasetSplit>] = [:]

        for record in cluster {
            guard let hash = record.contentHash, let split = record.split else { continue }

            var splits = splitsByHash[hash] ?? []
            splits.insert(split)
            if splits.count > 1 { return true }
            splitsByHash[hash] = splits
        }

        return false
    }
}
