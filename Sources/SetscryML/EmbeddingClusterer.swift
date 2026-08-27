//
//  EmbeddingClusterer.swift
//  Setscry
//
//  Created by Luis Resendez on 06/08/2026.
//

import Foundation

/// Groups embeddings into clusters of visually or semantically similar images.
///
/// Spherical k-means: because ``Embedding`` values are unit length, cosine
/// similarity is a dot product and a cluster centre is just the normalised mean
/// of its members. Initialisation is k-means++ driven by a fixed seed, so the
/// same folder always produces the same clusters. A clustering that reshuffles
/// between runs is not something a user can act on.
public enum EmbeddingClusterer {
    public struct Cluster: Identifiable, Sendable {
        public let id: Int
        /// Members ordered by how typical they are of the cluster, so the first
        /// few make a fair thumbnail summary.
        public let members: [URL]
        /// Mean similarity of members to the centre, 0...1. Low means the
        /// cluster is a loose grouping rather than a real theme.
        public let cohesion: Float
    }

    /// A reasonable number of clusters for `count` images.
    ///
    /// The usual √(n/2) rule, clamped so a small folder is not shattered and a
    /// huge one does not produce more groups than anyone will read.
    public static func suggestedClusterCount(for count: Int) -> Int {
        guard count > 3 else { return max(1, count) }
        let suggested = Int((Double(count) / 2).squareRoot().rounded())
        return min(max(suggested, 2), 24)
    }

    public static func cluster(
        _ embeddings: [URL: Embedding],
        into requestedCount: Int? = nil,
        iterations: Int = 25
    ) -> [Cluster] {
        let entries = embeddings
            .map { (url: $0.key, values: $0.value.values) }
            .sorted { $0.url.path < $1.url.path }

        guard let dimension = entries.first?.values.count, dimension > 0 else { return [] }
        let points = entries.map(\.values)
        // A single cluster is not special-cased: it runs through the same loop
        // so its reported cohesion is measured rather than assumed. Claiming
        // perfect cohesion for a group nobody measured would describe a mixed
        // pile as "very consistent" in the UI.
        let k = max(1, min(requestedCount ?? suggestedClusterCount(for: points.count), points.count))

        var centres = seedCentres(points: points, k: k, dimension: dimension)
        var assignments = [Int](repeating: 0, count: points.count)

        for _ in 0..<iterations {
            var changed = false

            for (index, point) in points.enumerated() {
                let best = nearestCentre(to: point, centres: centres)
                if assignments[index] != best {
                    assignments[index] = best
                    changed = true
                }
            }

            centres = recomputeCentres(
                points: points,
                assignments: assignments,
                k: k,
                dimension: dimension,
                previous: centres
            )

            if !changed { break }
        }

        return makeClusters(entries: entries, points: points, assignments: assignments, centres: centres)
    }

    // MARK: - k-means++

    private static func seedCentres(points: [[Float]], k: Int, dimension: Int) -> [[Float]] {
        var generator = SeededGenerator(seed: 0x5EED_C10D)
        var centres = [points[Int(generator.next(upperBound: UInt64(points.count)))]]

        while centres.count < k {
            // Distance to the closest chosen centre, squared, as the sampling
            // weight, the standard k-means++ spread.
            let weights = points.map { point -> Double in
                let best = centres.map { similarity(point, $0) }.max() ?? 0
                let distance = Double(1 - best)
                return distance * distance
            }

            let total = weights.reduce(0, +)
            guard total > 0 else { break }

            var target = Double(generator.next(upperBound: 1_000_000)) / 1_000_000 * total
            var chosen = points.count - 1
            for (index, weight) in weights.enumerated() {
                target -= weight
                if target <= 0 {
                    chosen = index
                    break
                }
            }
            centres.append(points[chosen])
        }

        return centres
    }

    private static func nearestCentre(to point: [Float], centres: [[Float]]) -> Int {
        var bestIndex = 0
        var bestScore = -Float.greatestFiniteMagnitude

        for (index, centre) in centres.enumerated() {
            let score = similarity(point, centre)
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        return bestIndex
    }

    private static func recomputeCentres(
        points: [[Float]],
        assignments: [Int],
        k: Int,
        dimension: Int,
        previous: [[Float]]
    ) -> [[Float]] {
        var sums = [[Float]](repeating: [Float](repeating: 0, count: dimension), count: k)
        var counts = [Int](repeating: 0, count: k)

        for (index, point) in points.enumerated() {
            let cluster = assignments[index]
            counts[cluster] += 1
            for axis in 0..<dimension {
                sums[cluster][axis] += point[axis]
            }
        }

        return (0..<k).map { cluster in
            // An emptied cluster keeps its old centre rather than collapsing.
            guard counts[cluster] > 0 else { return previous[cluster] }
            return normalized(sums[cluster])
        }
    }

    private static func makeClusters(
        entries: [(url: URL, values: [Float])],
        points: [[Float]],
        assignments: [Int],
        centres: [[Float]]
    ) -> [Cluster] {
        var grouped: [Int: [(url: URL, score: Float)]] = [:]

        for (index, entry) in entries.enumerated() {
            let cluster = assignments[index]
            grouped[cluster, default: []].append(
                (entry.url, similarity(points[index], centres[cluster]))
            )
        }

        // Every ordering below is a total order, and ids are assigned last.
        // Sorting only by size or score leaves ties to be broken by dictionary
        // iteration, which varies between runs, so the same folder would come
        // back in a different order each time.
        var summaries: [(members: [URL], cohesion: Float)] = []

        for members in grouped.values where !members.isEmpty {
            let ordered = members.sorted { first, second in
                if first.score == second.score {
                    return first.url.path < second.url.path
                }
                return first.score > second.score
            }

            let total = ordered.reduce(Float(0)) { $0 + $1.score }
            summaries.append((ordered.map(\.url), total / Float(ordered.count)))
        }

        summaries.sort { first, second in
            if first.members.count == second.members.count {
                return first.members[0].path < second.members[0].path
            }
            return first.members.count > second.members.count
        }

        return summaries.enumerated().map { index, summary in
            Cluster(id: index, members: summary.members, cohesion: summary.cohesion)
        }
    }

    // MARK: - Vector helpers

    private static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        var total: Float = 0
        for index in a.indices {
            total += a[index] * b[index]
        }
        return total
    }

    private static func normalized(_ values: [Float]) -> [Float] {
        let magnitude = values.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        return magnitude > 0 ? values.map { $0 / magnitude } : values
    }
}

/// Small deterministic generator so clustering is reproducible without
/// depending on the system random source.
private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next(upperBound: UInt64) -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return upperBound > 0 ? z % upperBound : 0
    }
}
