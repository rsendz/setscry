//
//  EmbeddingProvider.swift
//  Setscry
//
//  Created by Luis Resendez on 06/08/2026.
//

import Foundation

/// The seam between Setscry's analyses and whatever model produces embeddings.
///
/// Nothing above this protocol knows what a model is. Adding an MLX-backed CLIP
/// encoder means writing a new conformance, not touching analysis or UI code.
public protocol EmbeddingProvider: Sendable {
    /// Stable identifier persisted alongside vectors, so embeddings produced by
    /// different models are never compared to each other.
    var identifier: String { get }

    var displayName: String { get }

    /// Shown in the UI before a long run: what this model is, and whether using
    /// it downloads anything.
    var details: String { get }

    /// Loads or downloads whatever the backend needs. Called before the first
    /// `embed` so download cost is surfaced up front rather than mid-scan.
    func prepare() async throws

    func embed(imageAt url: URL) async throws -> Embedding

    /// Embeds a batch of images.
    ///
    /// A requirement rather than a convenience, so that a backend able to push a
    /// whole batch through in one pass gets to. Left to the default, a batching
    /// model would be called image by image and give up most of its speed.
    func embed(
        imagesAt urls: [URL],
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [URL: Embedding]
}

public extension EmbeddingProvider {
    func prepare() async throws {}

    func embed(imagesAt urls: [URL]) async throws -> [URL: Embedding] {
        try await embed(imagesAt: urls, onProgress: { _, _ in })
    }

    /// Embeds many images with bounded concurrency, reporting progress as each
    /// finishes. Failures are skipped rather than aborting the batch.
    func embed(
        imagesAt urls: [URL],
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [URL: Embedding] {
        guard !urls.isEmpty else { return [:] }

        let maxConcurrent = max(2, ProcessInfo.processInfo.activeProcessorCount)

        var results: [URL: Embedding] = [:]
        results.reserveCapacity(urls.count)

        await withTaskGroup(of: (URL, Embedding?).self) { group in
            var next = 0

            func addTask() {
                guard next < urls.count else { return }
                let url = urls[next]
                next += 1
                group.addTask { (url, try? await self.embed(imageAt: url)) }
            }

            for _ in 0..<Swift.min(maxConcurrent, urls.count) { addTask() }

            var completed = 0
            while let (url, embedding) = await group.next() {
                completed += 1
                if let embedding { results[url] = embedding }
                onProgress(completed, urls.count)
                addTask()
            }
        }

        try Task.checkCancellation()
        return results
    }
}

/// Backends that can also embed text, which is what turns the index into
/// "find images by describing them". CLIP-style models conform; Vision's
/// feature print does not.
public protocol TextEmbeddingProvider: EmbeddingProvider {
    func embed(text: String) async throws -> Embedding

    /// Embeds what someone typed into the search field. Separate from
    /// ``embed(text:)`` because a model trained on captions needs the query
    /// wrapped in the phrasing it was trained on, and only the backend knows
    /// what that is.
    func embed(searchQuery: String) async throws -> Embedding
}

public extension TextEmbeddingProvider {
    func embed(searchQuery: String) async throws -> Embedding {
        try await embed(text: searchQuery)
    }
}
