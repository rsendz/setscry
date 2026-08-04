//
//  ContentHasher.swift
//  Setscry
//
//  Created by Luis Resendez on 04/08/2026.
//

import CryptoKit
import Foundation

/// Streaming SHA-256 of a file's bytes, used for exact-duplicate detection.
///
/// Files are read in chunks so a folder of large images never loads whole
/// images into memory just to be hashed.
public enum ContentHasher {
    public static func sha256(ofFileAt url: URL, chunkSize: Int = 1 << 20) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
