//
//  ImageInspector.swift
//  Setscry
//
//  Created by Luis Resendez on 01/08/2026.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads an image file once and reports everything that can be known without ML:
/// its format, pixel dimensions, whether it actually decodes, and its perceptual
/// hash.
///
/// Decoding is done at thumbnail resolution. That is enough to prove the pixel
/// data is intact and is also the right input for the perceptual hash, so a
/// corruption check and a hash cost one decode rather than two.
public enum ImageInspector {
    public struct Inspection: Sendable {
        public let format: String?
        public let pixelSize: PixelSize?
        public let perceptualHash: PerceptualHash?
        public let colorSignature: ColorSignature?
        public let problem: ImageProblem?
    }

    /// Decoding at this size keeps large images cheap while leaving plenty of
    /// detail for the 9×8 hash grid.
    private static let decodeSize = 256

    public static func inspect(fileAt url: URL, byteSize: Int64) -> Inspection {
        guard byteSize > 0 else {
            return Inspection(
                format: nil,
                pixelSize: nil,
                perceptualHash: nil,
                colorSignature: nil,
                problem: .empty
            )
        }

        // Checked before decoding, because the decoder cannot be asked. See
        // `FileCompleteness`: a truncated JPEG, PNG or HEIC decodes without
        // complaint, and a truncated GIF or TIFF fails to open at all and would
        // otherwise be reported as "not an image" rather than as damaged.
        let completeness = FileCompleteness.check(fileAt: url, byteSize: byteSize)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            return Inspection(
                format: nil,
                pixelSize: nil,
                perceptualHash: nil,
                colorSignature: nil,
                problem: completeness == .truncated ? .truncated : .unreadable
            )
        }

        let format = formatName(of: source)
        let pixelSize = headerPixelSize(of: source)

        guard completeness != .truncated else {
            return Inspection(
                format: format,
                pixelSize: pixelSize,
                perceptualHash: nil,
                colorSignature: nil,
                problem: .truncated
            )
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: decodeSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return Inspection(
                format: format,
                pixelSize: pixelSize,
                perceptualHash: nil,
                colorSignature: nil,
                problem: .decodeFailed
            )
        }

        return Inspection(
            format: format,
            pixelSize: pixelSize ?? PixelSize(width: image.width, height: image.height),
            perceptualHash: PerceptualHasher.hash(image),
            colorSignature: ColorSignatureExtractor.signature(of: image),
            problem: nil
        )
    }

    /// Decodes a display-ready thumbnail. Shared with the UI so the app has one
    /// decoding path.
    public static func thumbnail(forFileAt url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func formatName(of source: CGImageSource) -> String? {
        guard let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier) else { return nil }

        return type.preferredFilenameExtension?.uppercased()
            ?? type.localizedDescription
            ?? identifier
    }

    private static func headerPixelSize(of source: CGImageSource) -> PixelSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }

        return PixelSize(width: width, height: height)
    }
}
