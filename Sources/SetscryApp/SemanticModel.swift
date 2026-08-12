//
//  SemanticModel.swift
//  Setscry
//
//  Created by Luis Resendez on 12/08/2026.
//

import Foundation
import Observation
import SetscryCore
import SetscryML
import SetscryMLX

/// Owns everything that depends on the CLIP model: downloading it, embedding a
/// folder, and the searches, clusters and label checks that follow.
///
/// Kept separate from `AppModel` so the deterministic half of the app has no
/// idea the ML layer exists — the folder scan, duplicate findings and health
/// report all work whether or not this is ever switched on.
@MainActor
@Observable
final class SemanticModel {
    enum Phase {
        case idle
        /// Started, but the first progress report hasn't arrived yet.
        case preparing
        case downloading(CLIPModelStore.Progress)
        case embedding(completed: Int, total: Int)
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var index: EmbeddingIndex?
    private(set) var clusters: [EmbeddingClusterer.Cluster] = []
    private(set) var labelSuggestions: [LabelSanityChecker.Suggestion] = []

    var searchText = ""
    private(set) var searchResults: [EmbeddingIndex.Match] = []
    private(set) var isSearching = false
    /// Set when the results came from "find similar to this image" rather than
    /// from typed text, so the view can say what it is comparing against.
    private(set) var searchSubject: ImageRecord?

    private let embedder = CLIPEmbedder()
    private var work: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    /// How large the download is and what it buys, shown before it starts.
    nonisolated var modelDescription: String { embedder.details }
    nonisolated var modelName: String { embedder.displayName }
    nonisolated var isModelDownloaded: Bool { embedder.isReady }
    nonisolated var deviceDescription: String { MLXRuntime.deviceDescription }
    /// False when this build has no compiled Metal kernels, in which case the
    /// model-backed views explain that instead of offering a download.
    nonisolated var isSupported: Bool { MLXRuntime.isAvailable }
    nonisolated var unsupportedReason: String { MLXRuntime.unavailableReason }

    var isBusy: Bool {
        switch phase {
        case .preparing, .downloading, .embedding: true
        default: false
        }
    }

    var isReady: Bool {
        if case .ready = phase { true } else { false }
    }

    // MARK: - Building the index

    func build(for analysis: DatasetAnalysis) {
        guard !isBusy else { return }

        work?.cancel()
        phase = .preparing

        // Byte-identical copies share an embedding, so only representatives are
        // sent through the model.
        let records = DuplicateFinder.representatives(of: analysis.records.filter(\.isUsable))
        let labels = Dictionary(
            analysis.records.compactMap { record in record.label.map { (record.url, $0) } },
            uniquingKeysWith: { first, _ in first }
        )

        work = Task { [weak self] in
            guard let self else { return }

            do {
                try await self.embedder.prepare { progress in
                    Task { @MainActor in self.report(download: progress) }
                }

                self.phase = .embedding(completed: 0, total: records.count)

                let embeddings = try await self.embed(records.map(\.url))
                try Task.checkCancellation()

                let index = EmbeddingIndex(
                    providerIdentifier: self.embedder.identifier,
                    embeddings: embeddings
                )
                let clusters = EmbeddingClusterer.cluster(embeddings)
                let suggestions = LabelSanityChecker.suggestions(
                    embeddings: embeddings, labels: labels
                )

                self.index = index
                self.clusters = clusters
                self.labelSuggestions = suggestions
                self.phase = .ready
            } catch is CancellationError {
                self.phase = .idle
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        work?.cancel()
        work = nil
        phase = .idle
    }

    func reset() {
        cancel()
        index = nil
        clusters = []
        labelSuggestions = []
        searchResults = []
        searchText = ""
        searchSubject = nil
    }

    /// Embeds in batches so progress is visible and memory stays bounded.
    private func embed(_ urls: [URL]) async throws -> [URL: Embedding] {
        var results: [URL: Embedding] = [:]
        results.reserveCapacity(urls.count)

        let batchSize = 16
        var start = 0

        while start < urls.count {
            try Task.checkCancellation()

            let batch = Array(urls[start..<min(start + batchSize, urls.count)])
            let embeddings = try await embedder.embed(imagesAt: batch)

            for (url, embedding) in zip(batch, embeddings) {
                results[url] = embedding
            }

            start += batch.count
            let completed = start
            phase = .embedding(completed: completed, total: urls.count)
        }

        return results
    }

    /// Ranks the folder by similarity to one of its own images.
    ///
    /// No model call is needed: the image was embedded during indexing, so this
    /// is a lookup and a sort over vectors already in memory.
    func findSimilar(to record: ImageRecord) {
        guard let index, index.embedding(for: record.url) != nil else { return }

        searchTask?.cancel()
        searchText = ""
        searchSubject = record
        isSearching = false
        searchResults = index.nearest(to: record.url, limit: 60)
    }

    func clearSearch() {
        searchTask?.cancel()
        searchText = ""
        searchSubject = nil
        searchResults = []
        isSearching = false
    }

    private func report(download progress: CLIPModelStore.Progress) {
        switch phase {
        case .preparing, .downloading:
            phase = .downloading(progress)
        default:
            break
        }
    }

    // MARK: - Search

    func search() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        searchTask?.cancel()
        guard !query.isEmpty, let index else {
            searchResults = []
            searchSubject = nil
            isSearching = false
            return
        }

        isSearching = true
        searchSubject = nil
        searchTask = Task { [weak self] in
            guard let self else { return }

            do {
                let vector = try await self.embedder.embed(searchQuery: query)
                try Task.checkCancellation()
                self.searchResults = index.nearest(to: vector, limit: 60)
            } catch is CancellationError {
                return
            } catch {
                self.searchResults = []
            }

            self.isSearching = false
        }
    }
}
