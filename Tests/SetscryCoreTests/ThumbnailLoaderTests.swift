//
//  ThumbnailLoaderTests.swift
//  Setscry
//
//  Created by Luis Resendez on 02/09/2026.
//

import CoreGraphics
import Foundation
import Testing
@testable import Setscry
@testable import SetscryCore

/// The loader caches decoded thumbnails, and the cache key is the part that
/// went wrong: it named the file but not the size, so whichever size was asked
/// for first was served to every later caller.
struct ThumbnailLoaderTests {
    @Test("The same file at two sizes gives two images, not the first one twice")
    func sizeIsPartOfTheIdentity() async throws {
        let folder = try ImageFixture.Folder()
        let url = folder.url.appendingPathComponent("photo.png")
        try ImageFixture.writePNG(seed: 1, size: 256, to: url)

        // Small first, which is the order that used to poison the cache: a list
        // row asks for 44 points long before a grid tile asks for 132.
        let small = try #require(await ThumbnailLoader.shared.thumbnail(for: url, maxPixelSize: 32))
        let large = try #require(await ThumbnailLoader.shared.thumbnail(for: url, maxPixelSize: 256))

        #expect(small.cgImage.width == 32)
        #expect(large.cgImage.width == 256)
    }

    @Test("Asking twice at one size reuses the decode")
    func repeatedRequestsAgree() async throws {
        let folder = try ImageFixture.Folder()
        let url = folder.url.appendingPathComponent("photo.png")
        try ImageFixture.writePNG(seed: 2, size: 128, to: url)

        let first = try #require(await ThumbnailLoader.shared.thumbnail(for: url, maxPixelSize: 64))
        let second = try #require(await ThumbnailLoader.shared.thumbnail(for: url, maxPixelSize: 64))

        #expect(first.cgImage.width == second.cgImage.width)
        // The cache hands back the very same image rather than decoding again.
        #expect(first.cgImage === second.cgImage)
    }

    @Test("A file that is not an image yields nothing rather than hanging")
    func unreadableFilesReturnNil() async throws {
        let folder = try ImageFixture.Folder()
        let url = folder.url.appendingPathComponent("broken.png")
        try ImageFixture.writeCorruptFile(to: url)

        #expect(await ThumbnailLoader.shared.thumbnail(for: url, maxPixelSize: 64) == nil)
    }

    /// A tile scrolled away cancels its `.task`, and the decode runs in a
    /// detached task that does not inherit that. The call must still come back
    /// rather than leaving the caller suspended.
    @Test("A cancelled request returns instead of hanging")
    func cancellationUnblocksTheCaller() async throws {
        let folder = try ImageFixture.Folder()
        let url = folder.url.appendingPathComponent("photo.png")
        try ImageFixture.writePNG(seed: 3, size: 512, to: url)

        let work = Task {
            await ThumbnailLoader.shared.thumbnail(for: url, maxPixelSize: 512)
        }
        work.cancel()

        // The assertion is that this returns at all, whatever it returns.
        _ = await work.value
    }
}
