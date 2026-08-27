//
//  EmbeddingIndex.swift
//  Setscry
//
//  Created by Luis Resendez on 06/08/2026.
//

import Foundation

/// An in-memory vector index over a dataset's embeddings.
///
/// Brute-force cosine search: exact, dependency-free, and fast enough for the
/// dataset sizes Setscry targets today. It sits behind a small API on purpose:
/// swapping in an approximate index later is a change to this one type.
public struct EmbeddingIndex: Sendable {
    public struct Match: Identifiable, Sendable {
        public var id: URL { url }
        public let url: URL
        public let similarity: Float
    }

    /// Which model produced these vectors. Vectors from different models are
    /// never comparable, so this is checked before searching.
    public let providerIdentifier: String
    private let entries: [(url: URL, embedding: Embedding)]

    public init(providerIdentifier: String, embeddings: [URL: Embedding]) {
        self.providerIdentifier = providerIdentifier
        self.entries = embeddings.map { ($0.key, $0.value) }
    }

    public var count: Int { entries.count }

    public func embedding(for url: URL) -> Embedding? {
        entries.first { $0.url == url }?.embedding
    }

    /// The closest images to a query vector, most similar first.
    public func nearest(to query: Embedding, limit: Int = 50, excluding excluded: Set<URL> = []) -> [Match] {
        entries
            .lazy
            .filter { !excluded.contains($0.url) }
            .map { Match(url: $0.url, similarity: query.similarity(to: $0.embedding)) }
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { $0 }
    }

    public func nearest(to url: URL, limit: Int = 50) -> [Match] {
        guard let query = embedding(for: url) else { return [] }
        return nearest(to: query, limit: limit, excluding: [url])
    }
}
