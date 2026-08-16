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

/// Owns everything that depends on a model: getting one ready, embedding a
/// folder, and the searches, clusters and label checks that follow.
///
/// Kept separate from `AppModel` so the deterministic half of the app has no
/// idea the ML layer exists — the folder scan, duplicate findings and health
/// report all work whether or not this is ever switched on.
@MainActor
@Observable
final class SemanticModel {
    /// Which model reads the images.
    ///
    /// The built-in one is the default because it costs nothing to start: it
    /// ships with macOS, so the model-backed views work the first time they are
    /// opened. CLIP is worth 606 MB only for what it adds — searching by
    /// description — so it is offered rather than assumed.
    enum Backend: String, CaseIterable {
        case builtIn
        case clip

        var title: String {
            switch self {
            case .builtIn: "Built into macOS"
            case .clip: "CLIP"
            }
        }
    }

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

    /// The chosen backend, remembered between launches.
    private(set) var backend: Backend

    private let featurePrint = FeaturePrintEmbedder()
    private let clip = CLIPEmbedder()
    private var stores: [Backend: EmbeddingStore] = [:]
    private var work: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    private static let backendKey = "semanticBackend"

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.backendKey)
        let chosen = saved.flatMap(Backend.init(rawValue:)) ?? .builtIn
        // A build without Metal kernels cannot run CLIP at all, so a remembered
        // choice of it falls back rather than failing on first use.
        backend = (chosen == .clip && !MLXRuntime.isAvailable) ? .builtIn : chosen
        Task { await refreshCacheSize() }
    }

    /// Vectors from different models are never comparable, so each backend gets
    /// its own cache and switching between them is not a reason to throw either
    /// away.
    private var store: EmbeddingStore {
        if let existing = stores[backend] { return existing }
        let store = EmbeddingStore(providerIdentifier: provider.identifier)
        stores[backend] = store
        return store
    }

    private var provider: any EmbeddingProvider {
        switch backend {
        case .builtIn: featurePrint
        case .clip: clip
        }
    }

    /// Text search needs a model with a text encoder, which only CLIP has.
    private var textProvider: (any TextEmbeddingProvider)? { provider as? TextEmbeddingProvider }

    func use(_ backend: Backend) {
        guard backend != self.backend else { return }
        cancel()
        self.backend = backend
        UserDefaults.standard.set(backend.rawValue, forKey: Self.backendKey)
        index = nil
        clusters = []
        labelSuggestions = []
        clearSearch()
        Task { await refreshCacheSize() }
    }

    /// What the current backend is and what using it costs, shown before it runs.
    var modelDescription: String { provider.details }
    var modelName: String { provider.displayName }
    var canSearchByText: Bool { textProvider != nil }
    /// True when the backend needs nothing fetched before it can run.
    var isModelReady: Bool { backend == .builtIn || clip.isReady }
    /// Where the work runs. Only CLIP goes through MLX, so saying so for the
    /// built-in model would be describing the wrong thing.
    var deviceDescription: String {
        switch backend {
        case .builtIn: "Runs on this Mac, using whatever accelerator Vision picks."
        case .clip: MLXRuntime.deviceDescription
        }
    }
    /// False when this build has no compiled Metal kernels. Only CLIP needs
    /// them; the built-in backend runs regardless.
    nonisolated var isCLIPSupported: Bool { MLXRuntime.isAvailable }
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
    private func prepareProvider() async throws {
        switch backend {
        case .builtIn:
            try await featurePrint.prepare()
        case .clip:
            try await clip.prepare { [weak self] progress in
                Task { @MainActor in self?.report(download: progress) }
            }
        }
    }

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
                try await self.prepareProvider()

                let embeddings = try await self.embed(records)
                try Task.checkCancellation()

                let index = EmbeddingIndex(
                    providerIdentifier: self.provider.identifier,
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
                await self.refreshCacheSize()
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

    /// Clears everything about the folder being looked at. Deliberately leaves
    /// the embedding cache alone: outliving a change of folder is the whole
    /// point of it.
    func reset() {
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
        var results = await store.cached(for: records)
        reusedCount = results.count

        let pending = records.filter { results[$0.url] == nil }
        phase = .embedding(completed: reusedCount, total: records.count)

        let batchSize = 16
        var start = 0

        while start < pending.count {
            try Task.checkCancellation()

            let batch = Array(pending[start..<min(start + batchSize, pending.count)])
            let embeddings = try await provider.embed(imagesAt: batch.map(\.url))

            var fresh: [(contentHash: String, embedding: Embedding)] = []
            for record in batch {
                guard let embedding = embeddings[record.url] else { continue }
                results[record.url] = embedding
                if let hash = record.contentHash {
                    fresh.append((contentHash: hash, embedding: embedding))
                }
            }

            // Written per batch rather than at the end, so quitting part-way
            // through a large folder keeps everything embedded so far.
            await store.append(fresh)

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
        // Only a backend with a text encoder can answer a typed query; with the
        // built-in one the view offers CLIP instead of failing silently.
        guard !query.isEmpty, let index, let textProvider else {
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
                let vector = try await textProvider.embed(searchQuery: query)
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
