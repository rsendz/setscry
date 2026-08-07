//
//  Embedding.swift
//  Setscry
//
//  Created by Luis Resendez on 06/08/2026.
//

import Foundation

/// A unit-length feature vector describing an image (or, for backends that
/// support it, a text query).
///
/// Storing vectors normalized means similarity is a plain dot product, which
/// keeps the search path simple no matter which backend produced the vector.
public struct Embedding: Hashable, Sendable {
    public let values: [Float]

    /// Normalizes on the way in. A zero vector is stored as-is and always scores
    /// zero similarity.
    public init(_ values: [Float]) {
        let magnitude = values.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        self.values = magnitude > 0 ? values.map { $0 / magnitude } : values
    }

    public var dimension: Int { values.count }

    /// Cosine similarity in `-1...1`, or `0` for mismatched dimensions.
    public func similarity(to other: Embedding) -> Float {
        guard values.count == other.values.count else { return 0 }

        var total: Float = 0
        for index in values.indices {
            total += values[index] * other.values[index]
        }
        return total
    }

    /// Cosine distance in `0...2`, for callers that prefer "smaller is closer".
    public func distance(to other: Embedding) -> Float {
        1 - similarity(to: other)
    }
}
