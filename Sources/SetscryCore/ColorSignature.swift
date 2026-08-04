//
//  ColorSignature.swift
//  Setscry
//
//  Created by Luis Resendez on 04/08/2026.
//

import CoreGraphics
import Foundation

/// A coarse colour fingerprint: the average colour of each cell of a 4×4 grid.
///
/// The perceptual hash is deliberately colourblind — it compares brightness, so
/// it survives re-encoding and colour-profile shifts. That also means it cannot
/// tell two recolourings of the same picture apart, which is a real pattern in
/// image sets (product shots in several colourways, recoloured graphics). Pairing
/// structure with a cheap colour comparison keeps both properties.
public struct ColorSignature: Hashable, Sendable {
    static let gridSize = 4

    /// How far two average colours may drift and still count as the same image.
    /// Measured against real files: resizing and re-encoding a photo moves this
    /// by a couple of levels, while a recoloured variant of the same artwork
    /// moves it by tens.
    public static let maximumMatchingDistance = 12

    /// Interleaved RGB, one triple per grid cell.
    public let samples: [UInt8]

    public init(samples: [UInt8]) {
        self.samples = samples
    }

    /// Mean absolute per-channel difference, 0...255.
    public func distance(to other: ColorSignature) -> Int {
        guard samples.count == other.samples.count, !samples.isEmpty else { return 255 }

        var total = 0
        for index in samples.indices {
            total += abs(Int(samples[index]) - Int(other.samples[index]))
        }
        return total / samples.count
    }
}
