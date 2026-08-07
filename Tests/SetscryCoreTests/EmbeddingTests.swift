//
//  EmbeddingTests.swift
//  Setscry
//
//  Created by Luis Resendez on 06/08/2026.
//

import Foundation
import Testing
@testable import SetscryML

/// A progress callback can be invoked from any task, so the tally needs its own
/// lock rather than a captured `var`.
private final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.withLock { value += 1 }
    }

    var count: Int {
        lock.withLock { value }
    }
}

@Suite("Embeddings")
struct EmbeddingTests {
    @Test("Vectors are normalized, so similarity is a dot product")
    func normalization() {
        let embedding = Embedding([3, 4])

        #expect(abs(embedding.values.reduce(0) { $0 + $1 * $1 } - 1) < 0.0001)
        #expect(abs(embedding.similarity(to: embedding) - 1) < 0.0001)
    }

    @Test("Orthogonal and opposite vectors score as expected")
    func similarityRange() {
        let right = Embedding([1, 0])
        let up = Embedding([0, 1])
        let left = Embedding([-1, 0])

        #expect(abs(right.similarity(to: up)) < 0.0001)
        #expect(abs(right.similarity(to: left) + 1) < 0.0001)
        #expect(abs(right.distance(to: right)) < 0.0001)
    }

    @Test("Mismatched dimensions score zero rather than crashing")
    func mismatchedDimensions() {
        #expect(Embedding([1, 0]).similarity(to: Embedding([1, 0, 0])) == 0)
    }

    @Test("The index finds the closest vector and excludes the query itself")
    func indexSearch() {
        let a = URL(fileURLWithPath: "/a.png")
        let b = URL(fileURLWithPath: "/b.png")
        let c = URL(fileURLWithPath: "/c.png")

        let index = EmbeddingIndex(
            providerIdentifier: "test",
            embeddings: [
                a: Embedding([1, 0]),
                b: Embedding([0.9, 0.1]),
                c: Embedding([0, 1]),
            ]
        )

        let matches = index.nearest(to: a, limit: 2)

        #expect(index.count == 3)
        #expect(matches.count == 2)
        #expect(matches.first?.url == b)
        #expect(!matches.contains { $0.url == a })
    }

    /// Exercises the real Vision backend end to end. Nothing is downloaded — the
    /// model ships with macOS — so this is safe to run in a normal test pass.
    ///
    /// This checks the plumbing (the request runs, the raw buffer parses, the
    /// vectors are well formed), not how well the model ranks images. The
    /// fixtures are synthetic noise, which has no semantic content for a feature
    /// print to separate; asserting on similarity ordering here would be testing
    /// Vision on inputs it was never meant to handle.
    @Test("Vision feature prints produce well-formed vectors for every image")
    func featurePrintEmbedder() async throws {
        let folder = try ImageFixture.Folder()
        let first = try ImageFixture.writePNG(seed: 21, size: 512, to: folder.url.appendingPathComponent("first.png"))
        let second = try ImageFixture.writePNG(seed: 88, size: 512, to: folder.url.appendingPathComponent("second.png"))

        let embedder = FeaturePrintEmbedder()
        try await embedder.prepare()

        let progress = ProgressCounter()
        let embeddings = try await embedder.embed(imagesAt: [first, second]) { _, _ in
            progress.increment()
        }

        #expect(embeddings.count == 2)
        #expect(progress.count == 2)

        let a = try #require(embeddings[first])
        let b = try #require(embeddings[second])

        #expect(a.dimension > 0)
        #expect(a.dimension == b.dimension)
        #expect(abs(a.similarity(to: a) - 1) < 0.0001)
        // Different images must at least produce different vectors.
        #expect(a.values != b.values)
    }
}
