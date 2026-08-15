//
//  EmbeddingStore.swift
//  Setscry
//
//  Created by Luis Resendez on 15/08/2026.
//

import Foundation
import SetscryCore

/// A durable cache of embeddings, keyed by image content.
///
/// Embedding a large folder is the slowest thing Setscry does, and until this
/// existed every reopen paid the full cost again. Keying on the SHA-256 the scan
/// already computes means the cache survives more than reopening: renaming a
/// file, moving it to another folder, or keeping a second copy of it all hit the
/// same entry, because the key describes the bytes rather than the path.
///
/// One file per provider, so vectors from different models can never be mixed —
/// a mismatch is a different filename, not a validation failure to handle.
public actor EmbeddingStore {
    public let providerIdentifier: String

    private let url: URL
    private let maximumEntries: Int
    private var entries: [String: Embedding] = [:]
    private var isLoaded = false
    /// Set once the first append has written a header, so appends know the
    /// dimension the file was created with.
    private var dimension: Int?

    public init(
        providerIdentifier: String,
        directory: URL = EmbeddingStore.defaultDirectory,
        maximumEntries: Int = 100_000
    ) {
        self.providerIdentifier = providerIdentifier
        self.maximumEntries = maximumEntries
        self.url = directory.appendingPathComponent("\(providerIdentifier).embeddings")
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Setscry", isDirectory: true)
            .appendingPathComponent("Embeddings", isDirectory: true)
    }

    public var count: Int { entries.count }

    public var fileSize: Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: - Loading

    /// Reads the cache from disk, returning how many entries are now available.
    ///
    /// Never throws. A cache that cannot be read is not an error the user needs
    /// to see — it just means the next run embeds from scratch, so a corrupt or
    /// unreadable file is discarded silently.
    @discardableResult
    public func load() -> Int {
        guard !isLoaded else { return entries.count }
        isLoaded = true

        guard let result = EmbeddingFile.read(at: url, providerIdentifier: providerIdentifier, dimension: nil) else {
            entries = [:]
            try? FileManager.default.removeItem(at: url)
            return 0
        }

        entries = result.entries
        // Taken from the header rather than from a vector, so a file that holds
        // a header and no records still appends at the right record size.
        dimension = result.header.dimension

        // Appending the same hash across sessions is normal; rewriting once the
        // file is mostly duplicates keeps reads from growing without bound.
        if result.recordsRead > entries.count * 2 || entries.count > maximumEntries {
            compact()
        }

        return entries.count
    }

    public func embedding(forContentHash hash: String) -> Embedding? { entries[hash] }

    /// The subset of `records` already embedded, keyed by URL so callers can
    /// merge it straight into their results.
    ///
    /// Two records sharing a hash both resolve to the same vector, which is what
    /// makes duplicates free.
    public func cached(for records: [ImageRecord]) -> [URL: Embedding] {
        var hits: [URL: Embedding] = [:]
        for record in records {
            guard let hash = record.contentHash, let embedding = entries[hash] else { continue }
            hits[record.url] = embedding
        }
        return hits
    }

    // MARK: - Writing

    /// Appends a batch. Called after every batch rather than at the end of a
    /// run, so quitting mid-embed loses one batch rather than all of the work.
    public func append(_ batch: [(contentHash: String, embedding: Embedding)]) {
        load()

        let usable = batch.filter { $0.embedding.dimension > 0 }
        guard let incoming = usable.first?.embedding.dimension else { return }

        // A provider that starts emitting a different vector size makes every
        // stored record unreadable, so the file starts over rather than mixing.
        if let existing = dimension, existing != incoming { removeAll() }
        dimension = incoming

        let matching = usable.filter { $0.embedding.dimension == incoming }
        guard !matching.isEmpty else { return }

        var payload = Data()
        for entry in matching {
            guard let record = EmbeddingFile.encodeRecord(
                contentHash: entry.contentHash, embedding: entry.embedding
            ) else { continue }
            payload.append(record)
            entries[entry.contentHash] = entry.embedding
        }
        guard !payload.isEmpty else { return }

        do {
            try ensureFileExists(dimension: incoming)
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        } catch {
            // A cache that cannot be written is still a working app; the next
            // run simply re-embeds. Nothing here is worth interrupting the user.
            return
        }

        if entries.count > maximumEntries { compact() }
    }

    public func removeAll() {
        entries = [:]
        dimension = nil
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Maintenance

    /// Rewrites the file with one record per hash, dropping the oldest entries
    /// if the cache has outgrown its cap.
    ///
    /// Trimming uses insertion order as a stand-in for recency, which is only an
    /// approximation — an exact LRU would need access times this format does not
    /// store, and the cap exists to bound disk use rather than to be precise.
    private func compact() {
        guard let dimension else { return }

        var kept = Array(entries)
        if kept.count > maximumEntries {
            kept = Array(kept.suffix(maximumEntries))
            entries = Dictionary(uniqueKeysWithValues: kept)
        }

        try? EmbeddingFile.write(
            kept.map { (contentHash: $0.key, embedding: $0.value) },
            header: EmbeddingFile.Header(dimension: dimension, providerIdentifier: providerIdentifier),
            to: url
        )
    }

    private func ensureFileExists(dimension: Int) throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: url.path) else { return }

        try manager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let header = EmbeddingFile.Header(dimension: dimension, providerIdentifier: providerIdentifier)
        try EmbeddingFile.encodeHeader(header).write(to: url, options: .atomic)
    }
}
