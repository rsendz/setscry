import Foundation
import Observation
import SetscryCore

@MainActor
@Observable
final class ComparisonModel {
    private(set) var folder: URL?
    private(set) var entries: [FolderComparison.Entry] = []
    private(set) var isRunning = false
    private(set) var hasResults = false
    private(set) var message: String?
    private(set) var progress = ScanProgress(phase: .discovering)
    private var work: Task<Void, Never>?
    private var generation = UUID()

    func compare(folder: URL, library: DatasetAnalysis) {
        clear()
        guard !FolderComparison.rootsOverlap(folder, library.root) else {
            message = "Choose a separate folder. The two folders cannot contain each other."
            return
        }
        self.folder = folder
        isRunning = true
        let id = generation
        work = Task { [weak self] in
            do {
                let candidates = try await DatasetScanner().scan(root: folder) { progress in
                    Task { @MainActor in
                        guard self?.generation == id else { return }
                        self?.progress = progress
                    }
                }
                try Task.checkCancellation()
                let comparison = Task.detached(priority: .userInitiated) {
                    try FolderComparison.compare(library: library.records, candidates: candidates)
                }
                let entries = try await withTaskCancellationHandler {
                    try await comparison.value
                } onCancel: { comparison.cancel() }
                guard let self, self.generation == id, !Task.isCancelled else { return }
                self.entries = entries
                self.isRunning = false
                self.hasResults = true
                self.work = nil
            } catch {
                guard let self, self.generation == id, !Task.isCancelled else { return }
                self.isRunning = false
                self.message = "Couldn't compare the folders: \(error.localizedDescription)"
                self.work = nil
            }
        }
    }

    func clear() {
        generation = UUID()
        work?.cancel()
        work = nil
        folder = nil
        entries = []
        isRunning = false
        hasResults = false
        message = nil
    }

    func invalidate() {
        guard folder != nil else { return }
        clear()
        message = "The library changed. Compare again to use the current findings."
    }
}
