//
//  PerceptualHasher.swift
//  Setscry
//
//  Created by Luis Resendez on 04/08/2026.
//

import CoreGraphics
import Foundation

/// Computes ``PerceptualHash`` values by reducing an image to a 9×8 grayscale
/// grid and recording, for each row, whether each pixel is brighter than the one
/// to its right.
public enum PerceptualHasher {
    /// Width is one wider than the hash grid so each row yields 8 comparisons.
    private static let sampleWidth = 9
    private static let sampleHeight = 8

    public static func hash(_ image: CGImage) -> PerceptualHash? {
        guard let pixels = grayscaleSamples(of: image) else { return nil }

        var bits: UInt64 = 0
        var bitIndex = 0

        for row in 0..<sampleHeight {
            let rowStart = row * sampleWidth
            for column in 0..<(sampleWidth - 1) {
                if pixels[rowStart + column] > pixels[rowStart + column + 1] {
                    bits |= (1 << UInt64(bitIndex))
                }
                bitIndex += 1
            }
        }

        return PerceptualHash(bits: bits)
    }

    private static func grayscaleSamples(of image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight)

        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: sampleWidth,
                      height: sampleHeight,
                      bitsPerComponent: 8,
                      bytesPerRow: sampleWidth,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  )
            else { return false }

            context.interpolationQuality = .medium
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight)
            )
            return true
        }

        return drawn ? pixels : nil
    }
}
