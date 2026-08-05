//
//  ImageFixture.swift
//  Setscry
//
//  Created by Luis Resendez on 04/08/2026.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Generates deterministic test images on disk so tests never depend on
/// checked-in binaries.
enum ImageFixture {
    /// A temporary folder that cleans itself up when the returned handle is released.
    final class Folder {
        let url: URL

        init() throws {
            url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("setscry-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: url)
        }

        func makeSubfolder(_ path: String) throws -> URL {
            let folder = url.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
    }

    /// Writes a PNG whose visual content is fully determined by `seed`, so the
    /// same seed at two sizes yields perceptually near-identical images and
    /// different seeds yield unrelated ones.
    @discardableResult
    static func writePNG(seed: UInt64, size: Int = 128, to url: URL) throws -> URL {
        try write(makeImage(seed: seed, size: size), to: url)
    }

    @discardableResult
    private static func write(_ image: CGImage, to url: URL) throws -> URL {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw Failure.couldNotWrite(url)
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure.couldNotWrite(url)
        }

        return url
    }

    /// Writes a striped image in the given colour. Two calls with different
    /// colours produce the same brightness structure in different hues — the
    /// exact case a brightness-only hash cannot tell apart.
    @discardableResult
    static func writeStripedPNG(
        foreground: (UInt8, UInt8, UInt8),
        size: Int = 128,
        to url: URL
    ) throws -> URL {
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw Failure.couldNotDraw
        }

        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        context.setFillColor(
            red: Double(foreground.0) / 255,
            green: Double(foreground.1) / 255,
            blue: Double(foreground.2) / 255,
            alpha: 1
        )

        let stripe = Double(size) / 8
        for index in stride(from: 0, to: 8, by: 2) {
            context.fill(
                CGRect(x: Double(index) * stripe, y: 0, width: stripe, height: Double(size))
            )
        }

        guard let image = context.makeImage() else { throw Failure.couldNotDraw }
        return try write(image, to: url)
    }

    /// A file with an image extension that contains bytes no decoder will accept.
    @discardableResult
    static func writeCorruptFile(to url: URL) throws -> URL {
        try Data("this is definitely not a png".utf8).write(to: url)
        return url
    }

    @discardableResult
    static func writeEmptyFile(to url: URL) throws -> URL {
        try Data().write(to: url)
        return url
    }

    // MARK: - Drawing

    /// An 8×8 grid of grayscale blocks driven by a SplitMix64 sequence. Block
    /// structure survives resizing, which is exactly what a perceptual hash
    /// should key on.
    private static func makeImage(seed: UInt64, size: Int) throws -> CGImage {
        let blocks = 8
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw Failure.couldNotDraw
        }

        var state = seed &* 0x9E37_79B9_7F4A_7C15
        let blockSize = Double(size) / Double(blocks)

        for row in 0..<blocks {
            for column in 0..<blocks {
                let gray = Double(nextRandom(&state) >> 56) / 255.0
                context.setFillColor(gray: gray, alpha: 1)
                context.fill(
                    CGRect(
                        x: Double(column) * blockSize,
                        y: Double(row) * blockSize,
                        width: blockSize,
                        height: blockSize
                    )
                )
            }
        }

        guard let image = context.makeImage() else { throw Failure.couldNotDraw }
        return image
    }

    private static func nextRandom(_ state: inout UInt64) -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    enum Failure: Error {
        case couldNotDraw
        case couldNotWrite(URL)
    }
}
