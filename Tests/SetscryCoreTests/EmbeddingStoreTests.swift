//
//  EmbeddingStoreTests.swift
//  Setscry
//
//  Created by Luis Resendez on 15/08/2026.
//

import Foundation
import Testing
@testable import SetscryCore
@testable import SetscryML

/// The cache is the one place where a bug is invisible until it has already
/// corrupted a session's results, so these lean on the failure modes rather
/// than the happy path: partial writes, wrong provider, duplicate keys.
@Suite("Embedding cache")
struct EmbeddingStoreTests {
    // MARK: - Helpers

    private func makeEmbedding(seed: Float, dimension: Int = 8) -> Embedding {
        Embedding((0..<dimension).map { Float($0) * seed + 1 })
    }

    private func hash(_ label: String) -> String {
        // Same shape as the SHA-256 hex the scanner produces: 64 hex characters.
        String(String(repeating: label, count: 64).prefix(64))
    }

    private func makeRecord(url: URL, contentHash: String?) -> ImageRecord {
        ImageRecord(
            url: url,
            relativePath: url.lastPathComponent,
            byteSize: 1,
            modifiedAt: nil,
            format: "png",
            pixelSize: nil,
            contentHash: contentHash,
            perceptualHash: nil,
            colorSignature: nil,
            problem: nil,
            label: nil,
            split: nil
        )
    }

    private func cacheURL(in folder: ImageFixture.Folder, provider: String) -> URL {
        folder.url.appendingPathComponent("\(provider).embeddings")
    }

    // MARK: - Tests

    @Test("Vectors survive a round trip through the file byte for byte")
    func roundTrip() async throws {
        let folder = try ImageFixture.Folder()
        let original = makeEmbedding(seed: 0.5)

        let writer = EmbeddingStore(providerIdentifier: "test.provider", directory: folder.url)
        await writer.append([(contentHash: hash("a"), embedding: original)])

        let reader = EmbeddingStore(providerIdentifier: "test.provider", directory: folder.url)
        #expect(await reader.load() == 1)

        let restored = try #require(await reader.embedding(forContentHash: hash("a")))
        // Exact equality, not approximate: re-normalizing on read would move the
        // low bits and quietly make every cached vector differ from a fresh one.
        #expect(restored.values == original.values)
    }

    @Test("An image the cache has never seen is a miss")
    func unknownHashMisses() async throws {
        let folder = try ImageFixture.Folder()
        let store = EmbeddingStore(providerIdentifier: "test.provider", directory: folder.url)

        await store.append([(contentHash: hash("a"), embedding: makeEmbedding(seed: 1))])

        #expect(await store.embedding(forContentHash: hash("b")) == nil)
    }

    @Test("Vectors from one model are never handed to another")
    func providersAreIsolated() async throws {
        let folder = try ImageFixture.Folder()

        let first = EmbeddingStore(providerIdentifier: "model.one", directory: folder.url)
        await first.append([(contentHash: hash("a"), embedding: makeEmbedding(seed: 1))])

        let second = EmbeddingStore(providerIdentifier: "model.two", directory: folder.url)
        #expect(await second.load() == 0)
        #expect(await second.embedding(forContentHash: hash("a")) == nil)
    }

    @Test("A file that isn't ours is discarded rather than reported")
    func corruptFileIsDiscarded() async throws {
        let folder = try ImageFixture.Folder()
        let url = cacheURL(in: folder, provider: "test.provider")
        try Data(repeating: 0xAB, count: 400).write(to: url)

        let store = EmbeddingStore(providerIdentifier: "test.provider", directory: folder.url)
        #expect(await store.load() == 0)

        // And the store still works afterwards, starting from an empty file.
        await store.append([(contentHash: hash("a"), embedding: makeEmbedding(seed: 1))])

        let reopened = EmbeddingStore(providerIdentifier: "test.provider", directory: folder.url)
        #expect(await reopened.load() == 1)
    }

    @Test("A record cut short by a crash is trimmed, not left to misalign the file")
    func tornRecordIsRepaired() async throws {
        let folder = try ImageFixture.Folder()
        let url = cacheURL(in: folder, provider: "test.provider")

        let store = EmbeddingStore(providerIdentifier: "test.provider", directory: folder.url)
        await store.append([
            (contentHash: hash("a"), embedding: makeEmbedding(seed: 1)),
            (contentHash: hash("b"), embedding: makeEmbedding(seed: 2)),
        ])

        // Simulate quitting mid-write: lop the tail off the last record.
        let full = try Data(contentsOf: url)
        try full.dropLast(9).write(to: url)

        let reopened = EmbeddingStore(providerIdentifier: "test.provider", directory: folder.url)
        #expect(await reopened.load() == 1)

        // Without truncation on load, this append would land at a misaligned
        // offset and every later read would return garbage.
        await reopened.append([(contentHash: hash("c"), embedding: makeEmbedding(seed: 3))])

        let final = EmbeddingStore(providerIdentifier: "test.provider", directory: folder.url)
        #expect(await final.load() == 2)
        #expect(await final.embedding(forContentHash: hash("a")) != nil)
        #expect(await final.embedding(forContentHash: hash("c")) != nil)
    }

    @Test("A file written with a different vector size is discarded")
    func dimensionMismatchIsDiscarded() async throws {
        let folder = try ImageFixture.Folder()
        let url = cacheURL(in: folder, provider: "test.provider")

        let header = EmbeddingFile.Header(dimension: 8, providerIdentifier: "test.provider")
        #expect(EmbeddingFile.read(at: url, providerIdentifier: "test.provider", dimension: 8) == nil)

        var data = EmbeddingFile.encodeHeader(header)
        data.append(try #require(EmbeddingFile.encodeRecord(
            contentHash: hash("a"), embedding: makeEmbedding(seed: 1, dimension: 8)
        )))
        try data.write(to: url)

        #expect(EmbeddingFile.read(at: url, providerIdentifier: "test.provider", dimension: 16) == nil)
        #expect(EmbeddingFile.read(at: url, providerIdentifier: "test.provider", dimension: 8) != nil)
    }

    @Test("Re-embedding the same image replaces the old vector instead of stacking up")
    func duplicateKeysCollapse() async throws {
        let folder = try ImageFixture.Folder()
        let later = makeEmbedding(seed: 9)

        let store = EmbeddingStore(providerIdentifier: "test.provider", directory: folder.url)
        await store.append([(contentHash: hash("a"), embedding: makeEmbedding(seed: 1))])
        await store.append([(contentHash: hash("a"), embedding: later)])

        let reopened = EmbeddingStore(providerIdentifier: "test.provider", directory: folder.url)
        #expect(await reopened.load() == 1)
        #expect(await reopened.embedding(forContentHash: hash("a"))?.values == later.values)
    }

    @Test("A file thick with duplicates is compacted on load")
    func compactionShrinksTheFile() async throws {
        let folder = try ImageFixture.Folder()
        let url = cacheURL(in: folder, provider: "test.provider")
        let hashes = ["a", "b", "c", "d", "e"].map(hash)

        let store = EmbeddingStore(providerIdentifier: "test.provider", directory: folder.url)
        for round in 1...5 {
            await store.append(hashes.map {
                (contentHash: $0, embedding: makeEmbedding(seed: Float(round)))
            })
        }

        let before = try #require(try FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? NSNumber).int64Value

        let reopened = EmbeddingStore(providerIdentifier: "test.provider", directory: folder.url)
        #expect(await reopened.load() == hashes.count)

        let after = try #require(try FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? NSNumber).int64Value
        #expect(after < before)

        // Compaction must not lose the newest vector for any key.
        let expected = makeEmbedding(seed: 5).values
        for key in hashes {
            #expect(await reopened.embedding(forContentHash: key)?.values == expected)
        }
    }

    @Test("Copies and renames of a cached image are hits, and unreadable files are skipped")
    func cacheIsKeyedByContentNotPath() async throws {
        let folder = try ImageFixture.Folder()
        let store = EmbeddingStore(providerIdentifier: "test.provider", directory: folder.url)
        let embedding = makeEmbedding(seed: 3)

        await store.append([(contentHash: hash("a"), embedding: embedding)])

        let original = makeRecord(url: folder.url.appendingPathComponent("cat.png"), contentHash: hash("a"))
        let renamed = makeRecord(url: folder.url.appendingPathComponent("moved/cat-2.png"), contentHash: hash("a"))
        let unreadable = makeRecord(url: folder.url.appendingPathComponent("broken.png"), contentHash: nil)

        let hits = await store.cached(for: [original, renamed, unreadable])

        #expect(hits.count == 2)
        #expect(hits[original.url]?.values == embedding.values)
        #expect(hits[renamed.url]?.values == embedding.values)
        #expect(hits[unreadable.url] == nil)
    }

    @Test("Outgrowing the cap drops the oldest entries, not arbitrary ones")
    func trimmingKeepsTheNewest() async throws {
        let folder = try ImageFixture.Folder()
        let keys = ["a", "b", "c", "d", "e", "f"].map(hash)

        let store = EmbeddingStore(
            providerIdentifier: "test.provider", directory: folder.url, maximumEntries: 3
        )
        for (index, key) in keys.enumerated() {
            await store.append([(contentHash: key, embedding: makeEmbedding(seed: Float(index + 1)))])
        }

        let reopened = EmbeddingStore(
            providerIdentifier: "test.provider", directory: folder.url, maximumEntries: 3
        )
        #expect(await reopened.load() == 3)

        // The last three written survive; the first three are gone.
        for key in keys.suffix(3) {
            #expect(await reopened.embedding(forContentHash: key) != nil)
        }
        for key in keys.prefix(3) {
            #expect(await reopened.embedding(forContentHash: key) == nil)
        }
    }

    @Test("Clearing the cache removes the file")
    func clearingRemovesTheFile() async throws {
        let folder = try ImageFixture.Folder()
        let url = cacheURL(in: folder, provider: "test.provider")

        let store = EmbeddingStore(providerIdentifier: "test.provider", directory: folder.url)
        await store.append([(contentHash: hash("a"), embedding: makeEmbedding(seed: 1))])
        #expect(await store.fileSize > 0)

        await store.removeAll()

        #expect(FileManager.default.fileExists(atPath: url.path) == false)
        #expect(await store.count == 0)
        #expect(await store.fileSize == 0)
    }
}
