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

        let digits = Array("0123456789abcdef".utf8)
        var hex: [UInt8] = []
        hex.reserveCapacity(64)
        for byte in hasher.finalize() {
            hex.append(digits[Int(byte >> 4)])
            hex.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: hex, as: UTF8.self)
    }
}
