//
//  EmbeddingIndex.swift
//  Setscry
//
//  Created by Luis Resendez on 06/08/2026.
//

import Accelerate
import Foundation

/// An in-memory vector index over a dataset's embeddings.
///
/// Brute-force cosine search, which is exact and dependency-free. The vectors
/// are held as one contiguous buffer rather than an array of arrays, so scoring
/// the whole folder is a single BLAS call over memory that is already in order,
/// and only the closest few are selected rather than sorting everything.
///
/// It sits behind a small API on purpose: swapping in an approximate index later
/// is a change to this one type.
public struct EmbeddingIndex: Sendable {
    public struct Match: Identifiable, Sendable {
        public var id: URL { url }
        public let url: URL
        public let similarity: Float
    }

    /// Which model produced these vectors. Vectors from different models are
    /// never comparable, so this is checked before searching.
    public let providerIdentifier: String

    private let urls: [URL]
    /// Row `i` of `matrix` belongs to `urls[i]`, `dimension` values apart.
    private let matrix: [Float]
    private let dimension: Int
    /// Lookup by URL, so finding an image's own vector is not a walk over every
    /// other one. `findSimilar` used to do that scan twice per invocation.
    private let positionByURL: [URL: Int]

    public init(providerIdentifier: String, embeddings: [URL: Embedding]) {
        self.providerIdentifier = providerIdentifier

        // Vectors of a different width cannot be compared, and one of them in
        // the buffer would misalign every row after it. The width to keep is the
        // one most vectors agree on, not whichever the dictionary happens to
        // yield first: an unordered `first` would let a single stray vector
        // evict the entire folder.
        var widths: [Int: Int] = [:]
        for embedding in embeddings.values { widths[embedding.dimension, default: 0] += 1 }
        let dimension = widths.max { a, b in
            a.value == b.value ? a.key < b.key : a.value < b.value
        }?.key ?? 0

        // Sorted so the buffer's layout, and so any tie in scoring, is the same
        // from one run to the next.
        let usable = embeddings.filter { $0.value.dimension == dimension }.sorted { $0.key.path < $1.key.path }

        self.dimension = dimension
        self.urls = usable.map(\.key)
        self.positionByURL = Dictionary(
            usable.enumerated().map { ($0.element.key, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )

        var matrix = [Float]()
        matrix.reserveCapacity(usable.count * dimension)
        for entry in usable { matrix.append(contentsOf: entry.value.values) }
        self.matrix = matrix
    }

    public var count: Int { urls.count }

    public func embedding(for url: URL) -> Embedding? {
        guard let position = positionByURL[url] else { return nil }
        let start = position * dimension
        return Embedding(normalized: Array(matrix[start ..< start + dimension]))
    }

    /// The closest images to a query vector, most similar first.
    public func nearest(to query: Embedding, limit: Int = 50, excluding excluded: Set<URL> = []) -> [Match] {
        guard limit > 0, count > 0, query.dimension == dimension else { return [] }

        // One matrix-vector product for the whole folder. Every vector is unit
        // length, so the dot product is already the cosine similarity.
        var scores = [Float](repeating: 0, count: count)
        matrix.withUnsafeBufferPointer { rows in
            query.values.withUnsafeBufferPointer { vector in
                cblas_sgemv(
                    CblasRowMajor, CblasNoTrans,
                    Int32(count), Int32(dimension),
                    1, rows.baseAddress, Int32(dimension),
                    vector.baseAddress, 1,
                    0, &scores, 1
                )
            }
        }

        return bestMatches(scores: scores, limit: limit, excluding: excluded)
    }

    public func nearest(to url: URL, limit: Int = 50) -> [Match] {
        guard let query = embedding(for: url) else { return [] }
        return nearest(to: query, limit: limit, excluding: [url])
    }

    /// Keeps only the top `limit` rather than sorting all n and dropping the
    /// rest. The result is identical; the work is not.
    private func bestMatches(scores: [Float], limit: Int, excluding excluded: Set<URL>) -> [Match] {
        var best: [Match] = []
        best.reserveCapacity(limit + 1)

        for (position, score) in scores.enumerated() {
            let url = urls[position]
            guard !excluded.contains(url) else { continue }

            // Once the shortlist is full, anything no better than its weakest
            // member cannot make it and needs no further work.
            if best.count == limit, score <= best[best.count - 1].similarity { continue }

            let match = Match(url: url, similarity: score)
            let insertion = best.firstIndex { $0.similarity < score } ?? best.count
            best.insert(match, at: insertion)
            if best.count > limit { best.removeLast() }
        }

        return best
    }
}
