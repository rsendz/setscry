//
//  LabelSanityChecker.swift
//  Setscry
//
//  Created by Luis Resendez on 06/08/2026.
//

import Foundation

/// Flags images that look unlike the rest of the folder they sit in.
///
/// The method is deliberately simple to explain: build a centre for each label
/// from its own images, then find images that sit closer to a different label's
/// centre than to their own. That is evidence worth a second look, not a
/// verdict: an unusual but correctly labelled photo will show up here too, and
/// the UI says so.
public enum LabelSanityChecker {
    public struct Suggestion: Identifiable, Sendable {
        public var id: URL { url }
        public let url: URL
        public let currentLabel: String
        /// The label whose centre this image is closest to.
        public let suggestedLabel: String
        /// Similarity to its own label's centre.
        public let currentSimilarity: Float
        /// Similarity to the suggested label's centre.
        public let suggestedSimilarity: Float

        /// How much better the other label fits. Larger means more surprising.
        public var margin: Float { suggestedSimilarity - currentSimilarity }
    }

    /// A label needs at least this many images before its centre means anything.
    public static let minimumImagesPerLabel = 4

    /// - Parameter minimumMargin: how much closer the other centre must be
    ///   before the image is worth surfacing. Raising it trades recall for
    ///   fewer false alarms.
    public static func suggestions(
        embeddings: [URL: Embedding],
        labels: [URL: String],
        minimumMargin: Float = 0.02
    ) -> [Suggestion] {
        var byLabel: [String: [[Float]]] = [:]
        for (url, embedding) in embeddings {
            guard let label = labels[url] else { continue }
            byLabel[label, default: []].append(embedding.values)
        }

        let centres = byLabel
            .filter { $0.value.count >= minimumImagesPerLabel }
            .compactMapValues(centre)

        guard centres.count > 1 else { return [] }

        var suggestions: [Suggestion] = []

        for (url, embedding) in embeddings {
            guard let label = labels[url], let own = centres[label] else { continue }

            let ownSimilarity = similarity(embedding.values, own)

            var bestLabel: String?
            var bestSimilarity = ownSimilarity

            for (candidate, centre) in centres where candidate != label {
                let score = similarity(embedding.values, centre)
                if score > bestSimilarity {
                    bestSimilarity = score
                    bestLabel = candidate
                }
            }

            guard let bestLabel, bestSimilarity - ownSimilarity >= minimumMargin else { continue }

            suggestions.append(
                Suggestion(
                    url: url,
                    currentLabel: label,
                    suggestedLabel: bestLabel,
                    currentSimilarity: ownSimilarity,
                    suggestedSimilarity: bestSimilarity
                )
            )
        }

        return suggestions.sorted { $0.margin > $1.margin }
    }

    private static func centre(of vectors: [[Float]]) -> [Float]? {
        guard let dimension = vectors.first?.count, dimension > 0 else { return nil }

        var sum = [Float](repeating: 0, count: dimension)
        for vector in vectors {
            for axis in 0..<dimension {
                sum[axis] += vector[axis]
            }
        }

        let magnitude = sum.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        return magnitude > 0 ? sum.map { $0 / magnitude } : nil
    }

    private static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var total: Float = 0
        for index in a.indices {
            total += a[index] * b[index]
        }
        return total
    }
}
