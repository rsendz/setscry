//
//  CLIPImageProcessor.swift
//  Setscry
//
//  Created by Luis Resendez on 08/08/2026.
//

import CoreGraphics
import Foundation
import ImageIO
import MLX

/// A `CGImage` is immutable and safe to read from any thread but is not marked
/// `Sendable`; this states that guarantee so decoded images can be produced
/// concurrently and gathered together.
struct DecodedImage: @unchecked Sendable {
    let index: Int
    let image: CGImage
}

/// Turns an image file into the tensor CLIP's vision tower expects.
///
/// Reproduces the reference preprocessing exactly: resize the shorter side to
/// the model's input size, centre-crop to a square, scale to `0...1`, then
/// normalise with the published channel means and deviations.
struct CLIPImageProcessor {
    let size: Int
    let mean: [Float]
    let standardDeviation: [Float]

    init(size: Int, configuration: CLIPPreprocessorConfiguration) {
        self.size = size
        self.mean = configuration.imageMean
        self.standardDeviation = configuration.imageStd
    }

    /// Decodes only as much of the file as the model can use.
    ///
    /// ImageIO can downsample while decoding, which is the difference between
    /// reading a 36-megapixel photo and reading a thumbnail of it. The limit is
    /// derived from the aspect ratio so that the *shorter* side lands at the
    /// model's input size: capping the longer side alone would leave a wide
    /// image too small and force it to be upscaled again during the crop.
    func decode(contentsOf url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        var limit = size * 2
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           width > 0, height > 0 {
            let longest = max(width, height)
            let shortest = min(width, height)
            limit = min(longest, Int((Double(size * longest) / Double(shortest)).rounded(.up)))
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(limit, size),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Produces an `[N, H, W, C]` batch — the channels-last layout MLX
    /// convolutions expect.
    func pixels(for images: [CGImage]) -> MLXArray {
        var values = [Float]()
        values.reserveCapacity(images.count * size * size * 3)

        for image in images {
            values.append(contentsOf: normalizedPixels(of: image))
        }

        return MLXArray(values, [images.count, size, size, 3])
    }

    private func normalizedPixels(of image: CGImage) -> [Float] {
        let bytesPerRow = size * 4
        var raw = [UInt8](repeating: 0, count: bytesPerRow * size)

        raw.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: size,
                      height: size,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  )
            else { return }

            // No flip: Core Graphics writes the first row of a bitmap context's
            // buffer as the top scanline of what it draws, so reading the buffer
            // in order already gives the picture the right way up. Adding the
            // usual flip transform here would feed every image in upside down —
            // which the vision tower is not invariant to.
            context.interpolationQuality = .high

            // Scaling by the longer edge ratio and centring performs the
            // "resize shortest side then centre crop" in a single draw.
            let scale = max(
                CGFloat(size) / CGFloat(image.width),
                CGFloat(size) / CGFloat(image.height)
            )
            let width = CGFloat(image.width) * scale
            let height = CGFloat(image.height) * scale

            context.draw(
                image,
                in: CGRect(
                    x: (CGFloat(size) - width) / 2,
                    y: (CGFloat(size) - height) / 2,
                    width: width,
                    height: height
                )
            )
        }

        var values = [Float](repeating: 0, count: size * size * 3)
        for pixel in 0..<(size * size) {
            let source = pixel * 4
            let destination = pixel * 3
            for channel in 0..<3 {
                let level = Float(raw[source + channel]) / 255
                values[destination + channel] =
                    (level - mean[channel]) / standardDeviation[channel]
            }
        }

        return values
    }
}
