//
//  SimilarityClusterer.swift
//  Setscry
//
//  Created by Luis Resendez on 04/08/2026.
//

import Foundation

/// Groups images that are "the same picture" into connected components.
///
/// Two images are linked when they agree on both structure (perceptual hashes
/// within `threshold` bits) and colour (average colours within
/// ``ColorSignature/maximumMatchingDistance``). Requiring both matters: the
/// perceptual hash is brightness-only, so on its own it treats two recolourings
/// of the same picture as identical.
///
/// Byte-identical files satisfy both conditions automatically, so exact copies
/// always cluster together.
enum SimilarityClusterer {
    /// Components of two or more images, largest first.
    ///
    /// This compares every pair. At tens of thousands of images that is a few
    /// hundred million cheap comparisons, which is acceptable; beyond that a
    /// metric-tree index would be the next step.
    static func clusters(of records: [ImageRecord], threshold: Int) -> [[ImageRecord]] {
        // Built in one pass so the record, its bits and its colour cannot drift
        // out of step, and so the inner loop needs no optional unwrapping.
        let hashed = records.compactMap { record in
            record.perceptualHash.map { (record: record, bits: $0.bits, color: record.colorSignature) }
        }
        guard hashed.count > 1 else { return [] }

        let candidates = hashed.map(\.record)
        let bits = hashed.map(\.bits)
        let colors = hashed.map(\.color)

        var unionFind = UnionFind(count: candidates.count)
        for i in 0..<candidates.count {
            for j in (i + 1)..<candidates.count
            where (bits[i] ^ bits[j]).nonzeroBitCount <= threshold
                && colorsMatch(colors[i], colors[j]) {
                unionFind.union(i, j)
            }
        }

        return unionFind.groups()
            .filter { $0.count > 1 }
            .map { indices in indices.map { candidates[$0] } }
            .sorted { $0.count > $1.count }
    }

    /// The widest perceptual gap inside a cluster, in bits.
    static func spread(of records: [ImageRecord]) -> Int {
        let bits = records.compactMap { $0.perceptualHash?.bits }
        var maximum = 0
        for i in 0..<bits.count {
            for j in (i + 1)..<bits.count {
                maximum = max(maximum, (bits[i] ^ bits[j]).nonzeroBitCount)
            }
        }
        return maximum
    }

    /// Missing signatures do not veto a match; structure alone decides then.
    private static func colorsMatch(_ a: ColorSignature?, _ b: ColorSignature?) -> Bool {
        guard let a, let b else { return true }
        return a.distance(to: b) <= ColorSignature.maximumMatchingDistance
    }
}
