//
//  ClusteringTests.swift
//  Setscry
//
//  Created by Luis Resendez on 04/08/2026.
//

import Foundation
import Testing
@testable import SetscryML

@Suite("Clustering and label checks")
struct ClusteringTests {
    /// Builds a vector near one of three well-separated directions, so the
    /// correct grouping is known in advance.
    private func vector(group: Int, jitter: Float, dimension: Int = 8) -> Embedding {
        var values = [Float](repeating: 0, count: dimension)
        values[group] = 1
        values[(group + 3) % dimension] = jitter
        return Embedding(values)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/dataset/\(name)")
    }

    @Test("Well-separated groups come back as separate clusters")
    func clustersSeparableData() {
        var embeddings: [URL: Embedding] = [:]
        for group in 0..<3 {
            for member in 0..<6 {
                embeddings[url("g\(group)-\(member).png")] = vector(
                    group: group, jitter: Float(member) * 0.01
                )
            }
        }

        let clusters = EmbeddingClusterer.cluster(embeddings, into: 3)

        #expect(clusters.count == 3)
        #expect(clusters.allSatisfy { $0.members.count == 6 })

        // Every member of a cluster should have come from the same group.
        for cluster in clusters {
            let groups = Set(cluster.members.map { $0.lastPathComponent.prefix(2) })
            #expect(groups.count == 1)
        }
    }

    @Test("Clustering the same input twice gives the same answer")
    func clusteringIsDeterministic() {
        var embeddings: [URL: Embedding] = [:]
        for group in 0..<4 {
            for member in 0..<5 {
                embeddings[url("g\(group)-\(member).png")] = vector(
                    group: group, jitter: Float(member) * 0.02
                )
            }
        }

        let first = EmbeddingClusterer.cluster(embeddings, into: 4)
        let second = EmbeddingClusterer.cluster(embeddings, into: 4)

        #expect(first.map(\.members) == second.map(\.members))
    }

    @Test("Tight groups report higher cohesion than mixed ones")
    func cohesionReflectsTightness() {
        let tight = [
            url("a.png"): Embedding([1, 0, 0]),
            url("b.png"): Embedding([0.99, 0.01, 0]),
        ]
        let mixed = [
            url("a.png"): Embedding([1, 0, 0]),
            url("b.png"): Embedding([0, 1, 0]),
        ]

        let tightCluster = EmbeddingClusterer.cluster(tight, into: 1)[0]
        let mixedCluster = EmbeddingClusterer.cluster(mixed, into: 1)[0]

        #expect(tightCluster.cohesion > mixedCluster.cohesion)
    }

    @Test("Suggested cluster counts stay in a readable range")
    func suggestedCounts() {
        #expect(EmbeddingClusterer.suggestedClusterCount(for: 2) == 2)
        #expect(EmbeddingClusterer.suggestedClusterCount(for: 50) == 5)
        // Even a very large folder stays browsable.
        #expect(EmbeddingClusterer.suggestedClusterCount(for: 500_000) == 24)
    }

    // MARK: - Label checks

    @Test("An image filed under the wrong label is flagged")
    func labelCheckFindsMisfiledImage() {
        var embeddings: [URL: Embedding] = [:]
        var labels: [URL: String] = [:]

        for member in 0..<6 {
            let cats = url("cat-\(member).png")
            embeddings[cats] = vector(group: 0, jitter: Float(member) * 0.01)
            labels[cats] = "cat"

            let dogs = url("dog-\(member).png")
            embeddings[dogs] = vector(group: 1, jitter: Float(member) * 0.01)
            labels[dogs] = "dog"
        }

        // A dog-looking image sitting in the cat folder.
        let stray = url("cat-stray.png")
        embeddings[stray] = vector(group: 1, jitter: 0.02)
        labels[stray] = "cat"

        let suggestions = LabelSanityChecker.suggestions(embeddings: embeddings, labels: labels)

        let flagged = suggestions.first
        #expect(flagged?.url == stray)
        #expect(flagged?.currentLabel == "cat")
        #expect(flagged?.suggestedLabel == "dog")
        #expect(suggestions.count == 1)
    }

    @Test("Consistent labels produce no suggestions")
    func labelCheckStaysQuietWhenConsistent() {
        var embeddings: [URL: Embedding] = [:]
        var labels: [URL: String] = [:]

        for member in 0..<6 {
            let cats = url("cat-\(member).png")
            embeddings[cats] = vector(group: 0, jitter: Float(member) * 0.01)
            labels[cats] = "cat"

            let dogs = url("dog-\(member).png")
            embeddings[dogs] = vector(group: 1, jitter: Float(member) * 0.01)
            labels[dogs] = "dog"
        }

        #expect(LabelSanityChecker.suggestions(embeddings: embeddings, labels: labels).isEmpty)
    }

    /// A label with only a couple of examples has no meaningful centre, and
    /// treating it as one would produce confident nonsense.
    @Test("Labels with too few images are ignored")
    func labelCheckIgnoresTinyLabels() {
        var embeddings: [URL: Embedding] = [:]
        var labels: [URL: String] = [:]

        for member in 0..<6 {
            let cats = url("cat-\(member).png")
            embeddings[cats] = vector(group: 0, jitter: Float(member) * 0.01)
            labels[cats] = "cat"
        }

        let lonely = url("rare-1.png")
        embeddings[lonely] = vector(group: 1, jitter: 0)
        labels[lonely] = "rare"

        #expect(LabelSanityChecker.suggestions(embeddings: embeddings, labels: labels).isEmpty)
    }
}
