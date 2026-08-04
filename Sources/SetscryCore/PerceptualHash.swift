//
//  PerceptualHash.swift
//  Setscry
//
//  Created by Luis Resendez on 04/08/2026.
//

import Foundation

/// A 64-bit difference hash (dHash) of an image's low-frequency structure.
///
/// Two images that differ only by resizing, re-compression or light editing land
/// within a few bits of each other; unrelated images sit around 32 bits apart.
public struct PerceptualHash: Hashable, Sendable {
    public let bits: UInt64

    public init(bits: UInt64) {
        self.bits = bits
    }

    /// Hamming distance: the number of differing bits, 0...64.
    public func distance(to other: PerceptualHash) -> Int {
        (bits ^ other.bits).nonzeroBitCount
    }

    public var hexString: String {
        String(format: "%016llx", bits)
    }
}
