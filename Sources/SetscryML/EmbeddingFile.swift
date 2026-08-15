//
//  EmbeddingFile.swift
//  Setscry
//
//  Created by Luis Resendez on 15/08/2026.
//

import Foundation

/// Reading and writing the on-disk embedding cache.
///
/// The format is deliberately dull: a fixed-size header followed by fixed-size
/// records, so appending is a seek to the end and a write, and reading is
/// arithmetic rather than parsing. That is what makes the cache safe to append
/// to after every batch — the cost of a crash is one truncated record, which
/// `read` detects and repairs.
///
/// ```
/// header   128 bytes   magic, format version, dimension, provider identifier
/// record   64 + 4d     content hash as hex ASCII, then Float32 little-endian
/// ```
///
/// Hashes are stored as the same 64-character hex string `ImageRecord` already
/// carries, rather than as 32 packed bytes. It costs 32 bytes per image and
/// removes every hex-conversion path from this file.
enum EmbeddingFile {
    static let magic = Array("SETSCRY\u{01}".utf8)
    static let formatVersion: UInt32 = 1
    static let headerSize = 128
    static let hashSize = 64

    /// Longest provider identifier that fits in the header's fixed field.
    static let maximumProviderBytes = headerSize - 20

    struct Header: Equatable {
        var dimension: Int
        var providerIdentifier: String
    }

    struct ReadResult {
        var header: Header
        var entries: [String: Embedding]
        /// Records read including duplicates, so the caller can decide to compact.
        var recordsRead: Int
        /// Set when the file ended mid-record and was truncated back to alignment.
        var repairedTornRecord: Bool
    }

    static func recordSize(dimension: Int) -> Int { hashSize + dimension * 4 }

    // MARK: - Encoding

    static func encodeHeader(_ header: Header) -> Data {
        var data = Data(count: headerSize)
        let provider = Array(header.providerIdentifier.utf8.prefix(maximumProviderBytes))

        data.replaceSubrange(0..<magic.count, with: magic)
        data.replaceSubrange(8..<12, with: littleEndianBytes(formatVersion))
        data.replaceSubrange(12..<16, with: littleEndianBytes(UInt32(header.dimension)))
        data.replaceSubrange(16..<20, with: littleEndianBytes(UInt32(provider.count)))
        data.replaceSubrange(20..<(20 + provider.count), with: provider)
        return data
    }

    static func encodeRecord(contentHash: String, embedding: Embedding) -> Data? {
        let hash = Array(contentHash.utf8)
        guard hash.count == hashSize else { return nil }

        var data = Data(hash)
        data.reserveCapacity(recordSize(dimension: embedding.dimension))
        for value in embedding.values {
            data.append(contentsOf: littleEndianBytes(value.bitPattern))
        }
        return data
    }

    // MARK: - Decoding

    static func decodeHeader(_ data: Data) -> Header? {
        guard data.count >= headerSize else { return nil }
        guard Array(data.prefix(magic.count)) == magic else { return nil }
        guard readUInt32(data, at: 8) == formatVersion else { return nil }

        let dimension = Int(readUInt32(data, at: 12))
        let providerLength = Int(readUInt32(data, at: 16))
        guard dimension > 0, providerLength > 0, providerLength <= maximumProviderBytes else { return nil }

        let providerBytes = data[(data.startIndex + 20)..<(data.startIndex + 20 + providerLength)]
        guard let provider = String(data: providerBytes, encoding: .utf8) else { return nil }

        return Header(dimension: dimension, providerIdentifier: provider)
    }

    /// Loads every record, or returns `nil` when the file cannot be used at all
    /// — wrong magic, wrong version, or a header that disagrees with what the
    /// caller expects. A `nil` return always means "discard this file", never
    /// "something went wrong that the user should hear about".
    static func read(at url: URL, providerIdentifier: String, dimension: Int?) -> ReadResult? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        guard let header = decodeHeader(data) else { return nil }
        guard header.providerIdentifier == providerIdentifier else { return nil }
        if let dimension, header.dimension != dimension { return nil }

        let stride = recordSize(dimension: header.dimension)
        let body = data.count - headerSize
        let whole = body / stride
        let torn = body % stride != 0

        var entries: [String: Embedding] = [:]
        entries.reserveCapacity(whole)

        for index in 0..<whole {
            let offset = headerSize + index * stride
            guard let hash = readHash(data, at: offset) else { continue }
            entries[hash] = readEmbedding(data, at: offset + hashSize, dimension: header.dimension)
        }

        // A record half-written when the app quit would misalign every append
        // that follows it, so the tail is cut back to a whole number of records.
        if torn {
            try? truncate(url, to: headerSize + whole * stride)
        }

        return ReadResult(header: header, entries: entries, recordsRead: whole, repairedTornRecord: torn)
    }

    /// Rewrites the file with one record per hash. Used to compact a file that
    /// has accumulated duplicates, and to enforce the entry cap.
    static func write(_ entries: [(contentHash: String, embedding: Embedding)], header: Header, to url: URL) throws {
        var data = encodeHeader(header)
        for entry in entries {
            guard entry.embedding.dimension == header.dimension else { continue }
            if let record = encodeRecord(contentHash: entry.contentHash, embedding: entry.embedding) {
                data.append(record)
            }
        }

        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent("." + url.lastPathComponent + ".tmp")
        try data.write(to: temporary, options: .atomic)

        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }

    // MARK: - Byte helpers

    /// Mapped data carries no alignment guarantee, so every scalar is read
    /// unaligned. `load(fromByteOffset:as:)` would trap here.
    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        return UInt32(littleEndian: value)
    }

    private static func readHash(_ data: Data, at offset: Int) -> String? {
        let start = data.startIndex + offset
        let bytes = data[start..<(start + hashSize)]
        guard let hash = String(data: bytes, encoding: .utf8), hash.count == hashSize else { return nil }
        return hash
    }

    private static func readEmbedding(_ data: Data, at offset: Int, dimension: Int) -> Embedding {
        var values = [Float]()
        values.reserveCapacity(dimension)
        for index in 0..<dimension {
            values.append(Float(bitPattern: readUInt32(data, at: offset + index * 4)))
        }
        // Written already normalized, so re-normalizing would only perturb the
        // low bits of a vector that is already unit length.
        return Embedding(normalized: values)
    }

    private static func littleEndianBytes(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    private static func truncate(_ url: URL, to length: Int) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(length))
    }
}
