//
//  ColorSignatureExtractor.swift
//  Setscry
//
//  Created by Luis Resendez on 04/08/2026.
//

import CoreGraphics
import Foundation

/// Builds ``ColorSignature`` values by averaging an image down to a 4×4 RGB grid.
public enum ColorSignatureExtractor {
    public static func signature(of image: CGImage) -> ColorSignature? {
        let side = ColorSignature.gridSize
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * side)

        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: side,
                      height: side,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }

            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }

        guard drawn else { return nil }

        // Drop the alpha channel; every cell contributes one RGB triple.
        var samples = [UInt8]()
        samples.reserveCapacity(side * side * 3)
        for cell in 0..<(side * side) {
            let offset = cell * 4
            samples.append(pixels[offset])
            samples.append(pixels[offset + 1])
            samples.append(pixels[offset + 2])
        }

        return ColorSignature(samples: samples)
    }
}
