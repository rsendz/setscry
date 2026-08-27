//
//  FeaturePrintEmbedder.swift
//  Setscry
//
//  Created by Luis Resendez on 06/08/2026.
//

import Foundation
import Vision

/// Embeddings from Vision's built-in image feature print.
///
/// This is the zero-friction backend: the model ships with macOS, so there is no
/// download, no bundled weights and no first-run delay. It captures visual
/// similarity well, which is what near-duplicate detection needs, but it has
/// no text encoder, so searching by description needs a CLIP-style backend
/// conforming to ``TextEmbeddingProvider``.
public struct FeaturePrintEmbedder: EmbeddingProvider {
    public enum Failure: LocalizedError {
        case unsupportedElementType

        public var errorDescription: String? {
            switch self {
            case .unsupportedElementType:
                "Vision returned a feature print in an unexpected numeric format."
            }
        }
    }

    public let identifier = "vision.featureprint.v2"
    public let displayName = "Vision Feature Print"
    public let details = "Built into macOS. Nothing to download, and images never leave this Mac."

    public init() {}

    public func embed(imageAt url: URL) async throws -> Embedding {
        let request = GenerateImageFeaturePrintRequest()
        let observation = try await request.perform(on: url)
        return try Self.embedding(from: observation)
    }

    static func embedding(from observation: FeaturePrintObservation) throws -> Embedding {
        let count = observation.elementCount

        switch observation.elementType {
        case .float:
            let values = observation.data.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self).prefix(count))
            }
            return Embedding(values)

        case .double:
            let values = observation.data.withUnsafeBytes { buffer in
                buffer.bindMemory(to: Double.self).prefix(count).map(Float.init)
            }
            return Embedding(values)

        @unknown default:
            throw Failure.unsupportedElementType
        }
    }
}
