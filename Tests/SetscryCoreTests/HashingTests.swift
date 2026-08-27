//
//  HashingTests.swift
//  Setscry
//
//  Created by Luis Resendez on 04/08/2026.
//

import Foundation
import Testing
@testable import SetscryCore

@Suite("Hashing")
struct HashingTests {
    @Test("Identical bytes produce identical content hashes")
    func contentHashMatchesForCopies() throws {
        let folder = try ImageFixture.Folder()
        let original = try ImageFixture.writePNG(seed: 1, to: folder.url.appendingPathComponent("a.png"))
        let copy = folder.url.appendingPathComponent("b.png")
        try FileManager.default.copyItem(at: original, to: copy)

        let hashA = try ContentHasher.sha256(ofFileAt: original)
        let hashB = try ContentHasher.sha256(ofFileAt: copy)

        #expect(hashA == hashB)
        #expect(hashA.count == 64)
    }

    @Test("Different images produce different content hashes")
    func contentHashDiffersForDifferentImages() throws {
        let folder = try ImageFixture.Folder()
        let a = try ImageFixture.writePNG(seed: 1, to: folder.url.appendingPathComponent("a.png"))
        let b = try ImageFixture.writePNG(seed: 2, to: folder.url.appendingPathComponent("b.png"))

        #expect(try ContentHasher.sha256(ofFileAt: a) != ContentHasher.sha256(ofFileAt: b))
    }

    @Test("A resized copy stays close in perceptual hash")
    func perceptualHashSurvivesResizing() throws {
        let folder = try ImageFixture.Folder()
        let large = try ImageFixture.writePNG(seed: 7, size: 512, to: folder.url.appendingPathComponent("large.png"))
        let small = try ImageFixture.writePNG(seed: 7, size: 96, to: folder.url.appendingPathComponent("small.png"))

        let hashLarge = try #require(inspect(large).perceptualHash)
        let hashSmall = try #require(inspect(small).perceptualHash)

        #expect(hashLarge.distance(to: hashSmall) <= DuplicateFinder.defaultNearThreshold)
    }

    @Test("Unrelated images stay far apart in perceptual hash")
    func perceptualHashSeparatesDifferentImages() throws {
        let folder = try ImageFixture.Folder()
        let a = try ImageFixture.writePNG(seed: 11, to: folder.url.appendingPathComponent("a.png"))
        let b = try ImageFixture.writePNG(seed: 999, to: folder.url.appendingPathComponent("b.png"))

        let hashA = try #require(inspect(a).perceptualHash)
        let hashB = try #require(inspect(b).perceptualHash)

        #expect(hashA.distance(to: hashB) > DuplicateFinder.defaultNearThreshold)
    }

    /// The perceptual hash compares brightness only, so a recoloured copy of the
    /// same artwork is structurally identical to it. The colour signature is what
    /// keeps those apart. Without it, every colourway of one design collapses
    /// into a single bogus duplicate group.
    @Test("Recolouring an image keeps its structure but changes its colour signature")
    func colorSignatureSeparatesRecolouredImages() throws {
        let folder = try ImageFixture.Folder()
        let red = try ImageFixture.writeStripedPNG(
            foreground: (200, 40, 40),
            to: folder.url.appendingPathComponent("red.png")
        )
        let blue = try ImageFixture.writeStripedPNG(
            foreground: (40, 40, 200),
            to: folder.url.appendingPathComponent("blue.png")
        )

        let redInspection = inspect(red)
        let blueInspection = inspect(blue)

        let redHash = try #require(redInspection.perceptualHash)
        let blueHash = try #require(blueInspection.perceptualHash)
        let redColor = try #require(redInspection.colorSignature)
        let blueColor = try #require(blueInspection.colorSignature)

        // Same stripes, so the brightness structure is close…
        #expect(redHash.distance(to: blueHash) <= DuplicateFinder.defaultNearThreshold)
        // …but the colours are not, which is what breaks the false match.
        #expect(redColor.distance(to: blueColor) > ColorSignature.maximumMatchingDistance)
    }

    @Test("A resized copy keeps its colour signature")
    func colorSignatureSurvivesResizing() throws {
        let folder = try ImageFixture.Folder()
        let large = try ImageFixture.writePNG(seed: 7, size: 512, to: folder.url.appendingPathComponent("large.png"))
        let small = try ImageFixture.writePNG(seed: 7, size: 96, to: folder.url.appendingPathComponent("small.png"))

        let a = try #require(inspect(large).colorSignature)
        let b = try #require(inspect(small).colorSignature)

        #expect(a.distance(to: b) <= ColorSignature.maximumMatchingDistance)
    }

    @Test("Hamming distance counts differing bits")
    func hammingDistance() {
        #expect(PerceptualHash(bits: 0b1011).distance(to: PerceptualHash(bits: 0b1000)) == 2)
        #expect(PerceptualHash(bits: .max).distance(to: PerceptualHash(bits: 0)) == 64)
    }

    private func inspect(_ url: URL) -> ImageInspector.Inspection {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ImageInspector.inspect(fileAt: url, byteSize: Int64(size))
    }
}
