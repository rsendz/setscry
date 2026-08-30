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

    /// Exercises the real Vision backend end to end. Nothing is downloaded,
    /// since that model ships with macOS, so this is safe in a normal test pass.
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


/// The index was rewritten to score with one BLAS call over a contiguous buffer
/// and to select the top matches rather than sort everything. Both are meant to
/// be invisible, so this pins the results against the obvious implementation.
struct EmbeddingIndexTests {
    private func vectors(count: Int, dimension: Int = 64, seed: UInt64 = 42) -> [URL: Embedding] {
        var state = seed
        var result: [URL: Embedding] = [:]

        for index in 0 ..< count {
            let values = (0 ..< dimension).map { _ -> Float in
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Float(Int32(bitPattern: UInt32(truncatingIfNeeded: state >> 32))) / Float(Int32.max)
            }
            result[URL(fileURLWithPath: "/root/\(index).png")] = Embedding(values)
        }

        return result
    }

    @Test("The index returns exactly what a naive scan and sort would")
    func matchesTheNaiveImplementation() throws {
        let embeddings = vectors(count: 300)
        let index = EmbeddingIndex(providerIdentifier: "test", embeddings: embeddings)
        let query = try #require(embeddings.values.first)

        let expected = embeddings
            .map { (url: $0.key, similarity: query.similarity(to: $0.value)) }
            .sorted { $0.similarity > $1.similarity }
            .prefix(60)

        let actual = index.nearest(to: query, limit: 60)

        #expect(actual.count == expected.count)
        for (got, want) in zip(actual, expected) {
            #expect(got.url == want.url)
            // BLAS may accumulate in a different order than a scalar loop.
            #expect(abs(got.similarity - want.similarity) < 1e-5)
        }
    }

    @Test("A vector round-trips through the contiguous buffer unchanged")
    func embeddingsSurviveStorage() throws {
        let embeddings = vectors(count: 20)
        let index = EmbeddingIndex(providerIdentifier: "test", embeddings: embeddings)

        for (url, original) in embeddings {
            let stored = try #require(index.embedding(for: url))
            #expect(stored.values == original.values)
        }
    }

    @Test("An unknown file has no vector and yields no matches")
    func unknownURLs() {
        let index = EmbeddingIndex(providerIdentifier: "test", embeddings: vectors(count: 5))
        let stranger = URL(fileURLWithPath: "/elsewhere/x.png")

        #expect(index.embedding(for: stranger) == nil)
        #expect(index.nearest(to: stranger).isEmpty)
    }

    @Test("Vectors of the wrong width are left out rather than misaligning the buffer")
    func mismatchedDimensionsAreDropped() {
        var embeddings = vectors(count: 4, dimension: 64)
        embeddings[URL(fileURLWithPath: "/root/odd.png")] = Embedding([1, 2, 3])

        let index = EmbeddingIndex(providerIdentifier: "test", embeddings: embeddings)

        #expect(index.count == 4)
        #expect(index.embedding(for: URL(fileURLWithPath: "/root/odd.png")) == nil)
    }

    /// The width to keep is the one most vectors agree on. Taking it from an
    /// arbitrary element of an unordered dictionary made this depend on hash
    /// ordering: it passed on one run and dropped every vector on the next.
    @Test("The width most vectors agree on wins, not whichever comes out first")
    func majorityWidthWins() {
        var embeddings = vectors(count: 6, dimension: 64)
        for index in 0 ..< 2 {
            embeddings[URL(fileURLWithPath: "/root/odd\(index).png")] = Embedding([1, 2, 3])
        }

        let index = EmbeddingIndex(providerIdentifier: "test", embeddings: embeddings)

        #expect(index.count == 6)
    }

    /// The minority being *wider* is the case a "largest wins" rule would get
    /// wrong, so it is worth stating separately.
    @Test("A wider minority does not evict the majority")
    func widerMinorityLoses() {
        var embeddings = vectors(count: 5, dimension: 8)
        for index in 0 ..< 2 {
            embeddings[URL(fileURLWithPath: "/root/wide\(index).png")] =
                Embedding(Array(repeating: Float(1), count: 512))
        }

        let index = EmbeddingIndex(providerIdentifier: "test", embeddings: embeddings)

        #expect(index.count == 5)
        #expect(index.embedding(for: URL(fileURLWithPath: "/root/wide0.png")) == nil)
    }

    /// Same vectors, different insertion order, same index. This is the property
    /// the original bug broke, and the one a single run cannot demonstrate.
    @Test("The index does not depend on the order the vectors arrived in")
    func buildIsOrderIndependent() throws {
        let base = vectors(count: 12, dimension: 64)
        let query = try #require(base.values.first)

        var reference: [URL]?
        for _ in 0 ..< 25 {
            // Rebuilding the dictionary from a shuffled list gives the hash
            // table a different layout to hand back.
            var shuffled: [URL: Embedding] = [:]
            for (url, embedding) in base.shuffled() { shuffled[url] = embedding }

            let index = EmbeddingIndex(providerIdentifier: "test", embeddings: shuffled)
            #expect(index.count == base.count)

            let order = index.nearest(to: query, limit: base.count).map(\.url)
            if let reference {
                #expect(order == reference)
            } else {
                reference = order
            }
        }
    }

    @Test("Asking for more than the index holds returns what there is")
    func limitBeyondCount() {
        let index = EmbeddingIndex(providerIdentifier: "test", embeddings: vectors(count: 3))
        let query = Embedding(Array(repeating: Float(1), count: 64))

        #expect(index.nearest(to: query, limit: 100).count == 3)
        #expect(index.nearest(to: query, limit: 0).isEmpty)
    }
}
