//
//  CLIPTests.swift
//  Setscry
//
//  Created by Luis Resendez on 08/08/2026.
//

import CoreGraphics
import Foundation
import Testing
@testable import SetscryMLX

/// Tests for the hand-written CLIP port.
///
/// The tokenizer and preprocessor tests run anywhere. The tests that need the
/// weights are skipped unless the model has already been downloaded, so a plain
/// `swift test` never pulls 600 MB; run the app once, or set
/// `SETSCRY_DOWNLOAD_MODEL=1`, to exercise them.
@Suite("CLIP")
struct CLIPTests {
    // MARK: - Tokenizer

    private func makeTokenizer() throws -> CLIPTokenizer? {
        let directory = CLIPModelStore(source: .vitBase32).directory
        let vocabulary = directory.appendingPathComponent("vocab.json")
        let merges = directory.appendingPathComponent("merges.txt")

        guard FileManager.default.fileExists(atPath: vocabulary.path),
              FileManager.default.fileExists(atPath: merges.path) else { return nil }

        return try CLIPTokenizer(vocabularyURL: vocabulary, mergesURL: merges)
    }

    /// Pins the tokenizer against ids that are documented properties of CLIP's
    /// vocabulary. A silently wrong tokenizer degrades every search result
    /// without ever raising an error, so this is the check worth being exact
    /// about.
    @Test("Familiar words tokenize to CLIP's published ids")
    func tokenizerMatchesKnownIDs() throws {
        guard let tokenizer = try makeTokenizer() else { return }

        #expect(tokenizer.encode("a photo of a cat") == [49406, 320, 1125, 539, 320, 2368, 49407])
        #expect(tokenizer.encode("a photo of a dog") == [49406, 320, 1125, 539, 320, 1929, 49407])
    }

    @Test("Tokenizing is case- and whitespace-insensitive")
    func tokenizerNormalizes() throws {
        guard let tokenizer = try makeTokenizer() else { return }

        let plain = tokenizer.encode("a photo of a cat")
        #expect(tokenizer.encode("A  PHOTO   of a CAT") == plain)
        #expect(tokenizer.encode("  a photo of a cat  ") == plain)
    }

    @Test("Long text is truncated with the end token intact")
    func tokenizerTruncates() throws {
        guard let tokenizer = try makeTokenizer() else { return }

        let ids = tokenizer.encode(String(repeating: "cat ", count: 200))

        #expect(ids.count == 77)
        #expect(ids.first == 49406)
        // The text encoder pools at the end token; losing it to truncation
        // would silently pool at an arbitrary position instead.
        #expect(ids.last == 49407)
    }

    @Test("Unusual characters still tokenize rather than being dropped")
    func tokenizerHandlesNonASCII() throws {
        guard let tokenizer = try makeTokenizer() else { return }

        let ids = tokenizer.encode("a café in München 🌅")

        #expect(ids.count > 2)
        #expect(ids.first == 49406)
        #expect(ids.last == 49407)
    }

    // MARK: - Preprocessing

    /// The vision tower is not orientation-invariant, and a bitmap context puts
    /// row zero at the bottom. Getting this wrong feeds every image in upside
    /// down — which degrades results without ever looking like a bug.
    @Test("Preprocessed pixels keep the image the right way up")
    func preprocessorPreservesOrientation() throws {
        // Building the tensor calls into MLX, which aborts the process rather
        // than throwing when its Metal kernels are missing.
        guard MLXRuntime.isAvailable else { return }

        let size = 224
        let processor = CLIPImageProcessor(size: size, configuration: .standard)

        // Top half white, bottom half black.
        guard let context = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Could not create the test image")
            return
        }
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 32, width: 64, height: 32))

        let image = try #require(context.makeImage())
        let pixels = processor.pixels(for: [image])

        #expect(pixels.shape == [1, size, size, 3])

        // Row 0 must be the white top of the picture, brighter than the last row.
        let values = pixels.asArray(Float.self)
        let firstRow = values[0..<(size * 3)].reduce(0, +)
        let lastRow = values[((size - 1) * size * 3)..<(size * size * 3)].reduce(0, +)
        #expect(firstRow > lastRow)
    }

    // MARK: - End to end

    private func makeEmbedder() async throws -> CLIPEmbedder? {
        guard MLXRuntime.isAvailable else { return nil }

        let embedder = CLIPEmbedder(source: .vitBase32)
        let wantsDownload = ProcessInfo.processInfo.environment["SETSCRY_DOWNLOAD_MODEL"] == "1"

        guard embedder.isReady || wantsDownload else { return nil }

        try await embedder.prepare()
        return embedder
    }

    /// The real proof that the port is correct: text and image embeddings have
    /// to land in the same space, so a description must rank the image it
    /// describes above unrelated ones. A wrong activation, a mis-mapped weight
    /// or a flipped image would all still produce plausible-looking vectors,
    /// but would fail this.
    @Test("A description ranks the image it describes first")
    func semanticSearchRanksCorrectly() async throws {
        guard let embedder = try await makeEmbedder() else { return }

        let folder = try ImageFixture.Folder()
        let red = try ImageFixture.writeStripedPNG(
            foreground: (220, 30, 30), size: 256,
            to: folder.url.appendingPathComponent("red-stripes.png")
        )
        let blue = try ImageFixture.writeStripedPNG(
            foreground: (30, 30, 220), size: 256,
            to: folder.url.appendingPathComponent("blue-stripes.png")
        )

        let images = try await embedder.embed(imagesAt: [red, blue])
        #expect(images.count == 2)
        #expect(images[0].dimension == 512)

        let redQuery = try await embedder.embed(searchQuery: "red stripes")
        let blueQuery = try await embedder.embed(searchQuery: "blue stripes")

        #expect(redQuery.similarity(to: images[0]) > redQuery.similarity(to: images[1]))
        #expect(blueQuery.similarity(to: images[1]) > blueQuery.similarity(to: images[0]))
    }

    /// Half precision is easy to get subtly wrong. The causal mask in
    /// particular is built by multiplying a 0/1 matrix by a large negative
    /// number; if that number overflows the type, the unmasked entries become
    /// `0 * infinity` — NaN — and every text embedding silently turns to NaN
    /// while the image path keeps working.
    @Test("Text embeddings are finite, not NaN")
    func textEmbeddingsAreFinite() async throws {
        guard let embedder = try await makeEmbedder() else { return }

        for query in ["a red car", "an aerial photograph of a landscape", "x"] {
            let embedding = try await embedder.embed(searchQuery: query)

            #expect(embedding.values.allSatisfy { $0.isFinite })
            // A normalised vector of real numbers has unit magnitude; an
            // all-zero or NaN vector does not.
            let magnitude = embedding.values.reduce(Float(0)) { $0 + $1 * $1 }
            #expect(abs(magnitude - 1) < 0.01)
        }
    }

    @Test("Image embeddings are finite, not NaN")
    func imageEmbeddingsAreFinite() async throws {
        guard let embedder = try await makeEmbedder() else { return }

        let folder = try ImageFixture.Folder()
        let image = try ImageFixture.writePNG(
            seed: 3, size: 256, to: folder.url.appendingPathComponent("image.png")
        )

        let embedding = try await embedder.embed(imageAt: image)

        #expect(embedding.values.allSatisfy { $0.isFinite })
        #expect(abs(embedding.values.reduce(Float(0)) { $0 + $1 * $1 } - 1) < 0.01)
    }

    @Test("The same image embeds identically every time")
    func embeddingIsDeterministic() async throws {
        guard let embedder = try await makeEmbedder() else { return }

        let folder = try ImageFixture.Folder()
        let image = try ImageFixture.writePNG(
            seed: 42, size: 256, to: folder.url.appendingPathComponent("image.png")
        )

        let first = try await embedder.embed(imageAt: image)
        let second = try await embedder.embed(imageAt: image)

        #expect(first.similarity(to: second) > 0.9999)
    }

    /// Batched and single-image paths must agree, since the app uses batching
    /// for folders and the single path for one-off work.
    @Test("Batching does not change the result")
    func batchingMatchesSingleImages() async throws {
        guard let embedder = try await makeEmbedder() else { return }

        let folder = try ImageFixture.Folder()
        let a = try ImageFixture.writePNG(seed: 1, size: 256, to: folder.url.appendingPathComponent("a.png"))
        let b = try ImageFixture.writePNG(seed: 2, size: 256, to: folder.url.appendingPathComponent("b.png"))

        let batched = try await embedder.embed(imagesAt: [a, b])
        let singleA = try await embedder.embed(imageAt: a)
        let singleB = try await embedder.embed(imageAt: b)

        #expect(batched[0].similarity(to: singleA) > 0.999)
        #expect(batched[1].similarity(to: singleB) > 0.999)
    }
}
