//
//  FileCompleteness.swift
//  Setscry
//
//  Created by Luis Resendez on 28/08/2026.
//

import Foundation

/// Whether a file carries the end marker its container format requires.
///
/// ImageIO cannot answer this. A source built from a file URL reports
/// `.statusComplete` whatever the file contains, `CGImageSourceGetStatusAtIndex`
/// agrees, and the JPEG decoder pads the missing scan lines rather than failing,
/// so a half-copied photo decodes to a full-size image with a grey band. Nothing
/// in the decode path notices. The end marker is the only signal that survives.
///
/// Only formats whose end is cheap to recognise are checked. Everything else
/// returns ``Verdict/unknown``, because claiming a file is damaged on no evidence
/// is worse than missing one.
enum FileCompleteness {
    enum Verdict {
        /// The file carries the end marker its format requires.
        case complete
        /// The file is missing it, so bytes are absent from the end.
        case truncated
        /// Not a format this can check. Never treat as a defect.
        case unknown
    }

    /// Reading the whole file would defeat the purpose, so only the head and the
    /// tail are touched. 64 bytes is more than any magic number needs.
    private static let headLength = 64

    /// A JPEG's `FF D9` should be the final two bytes, but some writers pad the
    /// tail. Searching a small window tolerates that without letting an `FF D9`
    /// from an embedded thumbnail, which lives near the start, count as the end.
    private static let jpegTailWindow = 64

    static func check(fileAt url: URL, byteSize: Int64) -> Verdict {
        guard byteSize > 0, let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }

        guard let head = try? handle.read(upToCount: headLength), head.count >= 12 else {
            return .unknown
        }

        if head.starts(with: [0xFF, 0xD8, 0xFF]) {
            return hasTail([0xFF, 0xD9], handle: handle, byteSize: byteSize, window: jpegTailWindow)
        }
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            // The IEND chunk is empty, so its CRC is the same in every PNG.
            return hasTail([0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82],
                           handle: handle, byteSize: byteSize, window: 0)
        }
        if head.starts(with: Array("GIF87a".utf8)) || head.starts(with: Array("GIF89a".utf8)) {
            return hasTail([0x3B], handle: handle, byteSize: byteSize, window: 0)
        }
        if head.starts(with: Array("RIFF".utf8)), head[8..<12].elementsEqual(Array("WEBP".utf8)) {
            // RIFF states its own length, so the file simply has to be that long.
            let declared = 8 + Int64(littleEndian32(head, at: 4))
            return declared <= byteSize ? .complete : .truncated
        }
        if head[4..<8].elementsEqual(Array("ftyp".utf8)) {
            return isoBMFFVerdict(handle: handle, byteSize: byteSize)
        }

        return .unknown
    }

    /// Whether the file ends with `marker`, allowing it to sit up to `window`
    /// bytes from the end.
    private static func hasTail(
        _ marker: [UInt8],
        handle: FileHandle,
        byteSize: Int64,
        window: Int
    ) -> Verdict {
        let length = Int64(marker.count + window)
        let offset = max(0, byteSize - length)

        guard (try? handle.seek(toOffset: UInt64(offset))) != nil,
              let tail = try? handle.readToEnd(), tail.count >= marker.count else {
            return .unknown
        }

        let bytes = [UInt8](tail)
        if bytes.suffix(marker.count).elementsEqual(marker) { return .complete }

        // Only JPEG passes a window, and only to skip trailing padding.
        guard window > 0 else { return .truncated }

        for start in stride(from: bytes.count - marker.count, through: 0, by: -1)
        where Array(bytes[start ..< start + marker.count]) == marker {
            // Everything after the marker must be padding rather than image data.
            return bytes[(start + marker.count)...].allSatisfy { $0 == 0x00 } ? .complete : .truncated
        }

        return .truncated
    }

    /// Walks an ISO base media file's top-level boxes, which is how HEIC, HEIF
    /// and AVIF can be checked: they carry no end marker, but every box states
    /// its own length, so a complete file is one whose boxes tile it exactly.
    ///
    /// Only the 8-byte headers are read, never the payloads.
    private static func isoBMFFVerdict(handle: FileHandle, byteSize: Int64) -> Verdict {
        var offset: Int64 = 0

        while offset + 8 <= byteSize {
            guard (try? handle.seek(toOffset: UInt64(offset))) != nil,
                  let header = try? handle.read(upToCount: 8), header.count == 8 else {
                return .unknown
            }

            var size = Int64(bigEndian32(header, at: 0))
            var headerLength: Int64 = 8

            if size == 1 {
                // The 64-bit form puts the real size in the eight bytes after the type.
                guard let large = try? handle.read(upToCount: 8), large.count == 8 else {
                    return .truncated
                }
                size = Int64(bitPattern: [UInt8](large).reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
                headerLength = 16
            } else if size == 0 {
                // A zero size means the box runs to the end, so it always fits.
                return .complete
            }

            guard size >= headerLength else { return .unknown }
            guard offset + size <= byteSize else { return .truncated }
            offset += size
        }

        return offset == byteSize ? .complete : .truncated
    }

    private static func bigEndian32(_ data: Data, at index: Int) -> UInt32 {
        let bytes = [UInt8](data)
        return (0 ..< 4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[index + $1]) }
    }

    private static func littleEndian32(_ data: Data, at index: Int) -> UInt32 {
        let bytes = [UInt8](data)
        return (0 ..< 4).reduce(UInt32(0)) { $0 | UInt32(bytes[index + $1]) << (8 * UInt32($1)) }
    }
}
