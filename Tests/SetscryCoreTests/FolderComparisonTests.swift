import Foundation
import Testing
@testable import SetscryCore
@testable import Setscry

struct FolderComparisonTests {
    @Test("Comparison separates exact, resized, new and unreadable images")
    func categories() async throws {
        let library = try ImageFixture.Folder()
        let incoming = try ImageFixture.Folder()
        try ImageFixture.writePNG(seed: 1, size: 128, to: library.url.appendingPathComponent("original.png"))
        try ImageFixture.writePNG(seed: 1, size: 128, to: incoming.url.appendingPathComponent("exact.png"))
        try ImageFixture.writePNG(seed: 1, size: 256, to: incoming.url.appendingPathComponent("resized.png"))
        try ImageFixture.writePNG(seed: 99, to: incoming.url.appendingPathComponent("new.png"))
        try ImageFixture.writeEmptyFile(to: incoming.url.appendingPathComponent("broken.png"))
        let scanner = DatasetScanner()
        let existing = try await scanner.scan(root: library.url, onProgress: { _ in })
        let candidates = try await scanner.scan(root: incoming.url, onProgress: { _ in })
        let entries = try FolderComparison.compare(library: existing, candidates: candidates)
        let kinds = Dictionary(uniqueKeysWithValues: entries.map { ($0.candidate.fileName, $0.kind) })
        #expect(kinds["exact.png"] == .exact)
        #expect(kinds["resized.png"] == .near)
        #expect(kinds["new.png"] == .new)
        #expect(kinds["broken.png"] == .unreadable)
        #expect(entries.first { $0.kind == .exact }?.matches.map(\.fileName) == ["original.png"])
    }

    @Test("Recolouring is not a visual match")
    func colourMismatch() async throws {
        let folder = try ImageFixture.Folder()
        try ImageFixture.writeStripedPNG(foreground: (220, 0, 0), to: folder.url.appendingPathComponent("red.png"))
        try ImageFixture.writeStripedPNG(foreground: (0, 0, 220), to: folder.url.appendingPathComponent("blue.png"))
        let records = try await DatasetScanner().scan(root: folder.url, onProgress: { _ in })
        let entries = try FolderComparison.compare(library: [records[0]], candidates: [records[1]])
        #expect(entries.first?.kind == .new)
    }

    @Test("Overlapping roots, including symlink aliases, are rejected")
    func overlappingRoots() throws {
        let folder = try ImageFixture.Folder()
        let nested = try folder.makeSubfolder("nested")
        #expect(FolderComparison.rootsOverlap(folder.url, nested))
        #expect(FolderComparison.rootsOverlap(nested, folder.url))
        let alias = folder.url.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: nested)
        #expect(FolderComparison.rootsOverlap(alias, nested))
        #expect(!FolderComparison.rootsOverlap(folder.url, URL(fileURLWithPath: folder.url.path + "-other")))
    }

    @Test("A cancelled comparison stops instead of publishing results")
    func cancellation() async {
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try FolderComparison.compare(library: [], candidates: [])
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    }
}
