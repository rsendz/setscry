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

/// Owns everything that depends on the model: loading it, reading a folder with
/// it, and the searches, clusters and label checks that follow.
///
/// Kept separate from `AppModel` so the deterministic half of the app has no
/// idea the ML layer exists. The folder scan, duplicate findings and health
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

    /// How many images this run took from the cache instead of embedding again.
    /// Surfaced during the run so the saved work is visible rather than implied.
    private(set) var reusedCount = 0
    /// Size of the cache on disk, so the menu item that clears it can say what
    /// clearing it frees.
    private(set) var cachedEmbeddingBytes: Int64 = 0

    private let clip = CLIPEmbedder()
    private let store: EmbeddingStore
    private var work: Task<Void, Never>?
    private var workID = UUID()
    private var searchTask: Task<Void, Never>?

    init() {
        store = EmbeddingStore(providerIdentifier: clip.identifier)
        Task { await refreshCacheSize() }
    }

    /// True when the weights are already here, which a packaged build always is.
    var isModelReady: Bool { clip.isReady }
    nonisolated var deviceDescription: String { MLXRuntime.deviceDescription }
    /// False when this build has no compiled Metal kernels, without which MLX
    /// cannot start at all.
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

    /// Gets the chosen backend ready. Only CLIP has anything to fetch, and only
    /// it reports download progress.
    private func prepareModel(id: UUID) async throws {
        try await clip.prepare { [weak self] progress in
            Task { @MainActor in
                guard self?.workID == id else { return }
                self?.report(download: progress)
            }
        }
    }

    func build(for analysis: DatasetAnalysis) {
        guard !isBusy else { return }

        work?.cancel()
        phase = .preparing
        let id = UUID()
        workID = id

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
                try Task.checkCancellation()
                try await self.prepareModel(id: id)
                try Task.checkCancellation()

                let embeddings = try await self.embed(records)
                try Task.checkCancellation()

                // Clustering is CPU work even when every embedding was cached.
                // Keep the window and Cancel button responsive while it runs.
                let providerIdentifier = self.clip.identifier
                let summary = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    let index = EmbeddingIndex(providerIdentifier: providerIdentifier, embeddings: embeddings)
                    let clusters = EmbeddingClusterer.cluster(embeddings)
                    try Task.checkCancellation()
                    let suggestions = LabelSanityChecker.suggestions(embeddings: embeddings, labels: labels)
                    return (index, clusters, suggestions)
                }
                let (index, clusters, suggestions) = try await withTaskCancellationHandler {
                    try await summary.value
                } onCancel: { summary.cancel() }
                try Task.checkCancellation()
                guard self.workID == id else { return }

                self.index = index
                self.clusters = clusters
                self.labelSuggestions = suggestions
                self.phase = .ready
                await self.refreshCacheSize()
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        workID = UUID()
        work?.cancel()
        work = nil
        phase = .idle
    }

    /// Clears everything about the folder being looked at. Deliberately leaves
    /// the embedding cache alone: outliving a change of folder is the whole
    /// point of it.
    func reset() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        cancel()
        reusedCount = 0
        index = nil
        clusters = []
        labelSuggestions = []
        searchResults = []
        searchText = ""
        searchSubject = nil
    }

    /// Embeds in batches so progress is visible and memory stays bounded, taking
    /// whatever the cache already holds instead of embedding it again.
    ///
    /// The cache is keyed by file content, so this skips more than images seen in
    /// a previous session: renamed files, copies, and images moved in from another
    /// folder all arrive already embedded.
    private func embed(_ records: [ImageRecord]) async throws -> [URL: Embedding] {
        await store.load()
        try Task.checkCancellation()
        var results = await store.cached(for: records)
        try Task.checkCancellation()
        reusedCount = results.count

        let pending = records.filter { results[$0.url] == nil }
        phase = .embedding(completed: reusedCount, total: records.count)

        let batchSize = 32
        var start = 0

        while start < pending.count {
            try Task.checkCancellation()

            let batch = Array(pending[start..<min(start + batchSize, pending.count)])
            // The whole batch goes through the model in one pass, which is most
            // of the speed of a transformer.
            let embeddings = try await clip.embed(imagesAt: batch.map(\.url))
            try Task.checkCancellation()

            var fresh: [(contentHash: String, embedding: Embedding)] = []
            for (record, embedding) in zip(batch, embeddings) {
                results[record.url] = embedding
                if let hash = record.contentHash {
                    fresh.append((contentHash: hash, embedding: embedding))
                }
            }

            // Written per batch rather than at the end, so quitting part-way
            // through a large folder keeps everything embedded so far.
            await store.append(fresh)
            try Task.checkCancellation()

            start += batch.count
            phase = .embedding(completed: reusedCount + start, total: records.count)
        }

        return results
    }

    func clearCachedEmbeddings() async {
        await store.removeAll()
        await refreshCacheSize()
    }

    private func refreshCacheSize() async {
        cachedEmbeddingBytes = await store.fileSize
    }

    /// Ranks the folder by similarity to one of its own images.
    ///
    /// No model call is needed: the image was embedded during indexing, so this
    /// is a lookup and a sort over vectors already in memory.
    func findSimilar(to record: ImageRecord) {
        // Looked up once and reused. Testing for the vector and then asking for
        // it again by URL walked the whole folder twice before scoring it.
        guard let index, let vector = index.embedding(for: record.url) else { return }

        searchTask?.cancel()
        searchText = ""
        searchSubject = record
        isSearching = false
        searchResults = index.nearest(to: vector, limit: 60, excluding: [record.url])
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
                let vector = try await self.clip.embed(searchQuery: query)
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
