//
//  CLIPEmbedder.swift
//  Setscry
//
//  Created by Luis Resendez on 08/08/2026.
//

import CoreGraphics
import Foundation
import MLX
import MLXNN
import SetscryCore
import SetscryML

/// A CLIP backend running locally through MLX.
///
/// Conforms to ``TextEmbeddingProvider``, so it plugs in wherever the Vision
/// feature print does but additionally puts text and images in one shared
/// space, which is what makes searching images by description possible.
///
/// The model is an actor because MLX evaluation is not safe to drive from
/// several tasks at once, and because loading half a gigabyte of weights should
/// happen exactly once.
public actor CLIPEmbedder: TextEmbeddingProvider {
    public enum Failure: LocalizedError {
        case modelNotLoaded
        case decodeFailed(URL)
        case mlxUnavailable

        public var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                "The model is not loaded yet."
            case .decodeFailed(let url):
                "Couldn't read \(url.lastPathComponent) as an image."
            case .mlxUnavailable:
                MLXRuntime.unavailableReason
            }
        }
    }

    public nonisolated let identifier: String
    public nonisolated let displayName: String
    public nonisolated let details: String

    private let source: CLIPModelSource
    private let store: CLIPModelStore

    private var model: CLIPModel?
    private var tokenizer: CLIPTokenizer?
    private var processor: CLIPImageProcessor?

    public init(source: CLIPModelSource = .vitBase32) {
        self.source = source
        self.store = CLIPModelStore(source: source)
        self.identifier = source.identifier
        self.displayName = source.displayName
        self.details = "Runs on this Mac. Nothing is uploaded, and nothing is downloaded."
    }

    public nonisolated var isReady: Bool { store.isReady }

    public nonisolated var modelDirectory: URL { store.directory }

    /// Downloads the weights if needed, then loads them. Safe to call
    /// repeatedly; the work happens once.
    public func prepare() async throws {
        try await prepare(onDownloadProgress: { _ in })
    }

    public func prepare(
        onDownloadProgress: @escaping @Sendable (CLIPModelStore.Progress) -> Void
    ) async throws {
        guard model == nil else { return }

        // Checked before anything touches MLX: without the kernels, the first
        // call into it takes the whole process down.
        guard MLXRuntime.isAvailable else { throw Failure.mlxUnavailable }
        MLXRuntime.configureDefaultDevice()

        let directory = try await store.download(onProgress: onDownloadProgress)

        let configuration = try CLIPConfiguration.load(
            from: directory.appendingPathComponent("config.json")
        )
        let preprocessor = CLIPPreprocessorConfiguration.load(
            from: directory.appendingPathComponent("preprocessor_config.json")
        )

        let model = CLIPModel(configuration: configuration)
        try Self.loadWeights(
            into: model,
            from: directory.appendingPathComponent("model.safetensors")
        )
        eval(model)

        self.model = model
        self.tokenizer = try CLIPTokenizer(
            vocabularyURL: directory.appendingPathComponent("vocab.json"),
            mergesURL: directory.appendingPathComponent("merges.txt")
        )
        self.processor = CLIPImageProcessor(
            size: configuration.visionConfig.imageSize,
            configuration: preprocessor
        )
    }

    // MARK: - Embedding

    public func embed(imageAt url: URL) async throws -> SetscryML.Embedding {
        try await embed(imagesAt: [url]).first ?? { throw Failure.decodeFailed(url) }()
    }

    /// Embeds several images in one forward pass.
    ///
    /// Batching matters here: the per-call overhead of a transformer is large
    /// relative to one 224×224 image, so a whole folder runs several times
    /// faster in batches than one at a time.
    public func embed(imagesAt urls: [URL]) async throws -> [SetscryML.Embedding] {
        guard let model, let processor else { throw Failure.modelNotLoaded }
        guard !urls.isEmpty else { return [] }

        let images = try await decode(urls, with: processor)
        // Input and weights must share a type, or MLX promotes back to float32
        // and the half-precision weights buy nothing.
        let pixels = processor.pixels(for: images).asType(Self.computeType)
        let features = model.imageFeatures(pixels)
        eval(features)

        return embeddings(from: features)
    }

    /// The batched entry point the app uses, keyed by URL.
    ///
    /// Overrides the protocol's concurrent default so the whole batch still goes
    /// through the model in one pass.
    public func embed(
        imagesAt urls: [URL],
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [URL: SetscryML.Embedding] {
        let embeddings = try await embed(imagesAt: urls)
        onProgress(embeddings.count, urls.count)
        return Dictionary(uniqueKeysWithValues: zip(urls, embeddings))
    }

    public func embed(text: String) async throws -> SetscryML.Embedding {
        guard let model, let tokenizer else { throw Failure.modelNotLoaded }

        let tokens = tokenizer.encode(text)
        let features = model.textFeatures(MLXArray(tokens, [1, tokens.count]))
        eval(features)

        return embeddings(from: features)[0]
    }

    /// CLIP was trained on captions, not bare words, so the prompt template is
    /// part of using the model correctly rather than a flourish.
    public func embed(searchQuery: String) async throws -> SetscryML.Embedding {
        try await embed(text: "a photo of \(searchQuery)")
    }

    /// Decodes a batch concurrently.
    ///
    /// On a folder of large photographs, JPEG and HEIC decoding costs more than
    /// the forward pass does, and doing it one file at a time inside this actor
    /// leaves every core but one idle.
    private nonisolated func decode(
        _ urls: [URL],
        with processor: CLIPImageProcessor
    ) async throws -> [CGImage] {
        let decoded = await withTaskGroup(of: DecodedImage?.self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    processor.decode(contentsOf: url).map {
                        DecodedImage(index: index, image: $0)
                    }
                }
            }

            var results: [DecodedImage] = []
            results.reserveCapacity(urls.count)
            for await decoded in group {
                if let decoded { results.append(decoded) }
            }
            return results
        }

        guard decoded.count == urls.count else {
            let found = Set(decoded.map(\.index))
            let missing = urls.indices.first { !found.contains($0) } ?? 0
            throw Failure.decodeFailed(urls[missing])
        }

        // Concurrent completion order is arbitrary; restore the caller's order
        // so embeddings line up with the URLs they were asked for.
        return decoded.sorted { $0.index < $1.index }.map(\.image)
    }

    private func embeddings(from features: MLXArray) -> [SetscryML.Embedding] {
        let rows = features.dim(0)
        let columns = features.dim(1)
        let values = features.asType(.float32).asArray(Float.self)

        return (0..<rows).map { row in
            let start = row * columns
            // `Embedding` normalises on the way in, so cosine similarity in the
            // index is a plain dot product.
            return SetscryML.Embedding(Array(values[start..<(start + columns)]))
        }
    }

    // MARK: - Weights

    /// Inference runs in half precision.
    ///
    /// The published checkpoints are float32, which doubles both the memory and
    /// the bandwidth every layer needs for no benefit here. Half precision is
    /// what CLIP is normally served in, and retrieval ranks images by relative
    /// similarity, which is far coarser than the precision difference.
    static let computeType: DType = .float16

    static func loadWeights(into model: CLIPModel, from url: URL) throws {
        var weights: [String: MLXArray] = [:]

        for (key, value) in try loadArrays(url: url) {
            // Buffers, not parameters; the model has no matching entry.
            if key.hasSuffix("position_ids") { continue }
            // Only used for the training objective's temperature.
            if key == "logit_scale" { continue }

            if key.hasSuffix("patch_embedding.weight") {
                // Checkpoints store convolution weights as
                // [out, in, kH, kW]; MLX expects [out, kH, kW, in].
                weights[key] = value.transposed(0, 2, 3, 1).asType(computeType)
            } else {
                weights[key] = value.asType(computeType)
            }
        }

        // `.all` fails loudly on a missing, unused or mis-shaped parameter.
        // For a hand-written port that is the difference between a clear error
        // and silently poor results.
        try model.update(parameters: ModuleParameters.unflattened(weights), verify: .all)
    }
}
