import Foundation
import Testing
@testable import SetscryCore
@testable import Setscry

struct FolderComparisonTests {
    @Test("Direct comparison preserves order, threshold boundaries and exact precedence")
    func directMatches() throws {
        func record(_ name: String, bits: UInt64?, hash: String? = nil,
                    color: UInt8? = 128, problem: ImageProblem? = nil) -> ImageRecord {
            ImageRecord(url: URL(fileURLWithPath: "/\(name)"), relativePath: name,
                byteSize: 100, modifiedAt: nil, format: "PNG", pixelSize: nil,
                contentHash: hash ?? name, perceptualHash: bits.map(PerceptualHash.init),
                colorSignature: color.map { ColorSignature(samples: [UInt8](repeating: $0, count: 48)) },
                problem: problem, label: nil, split: nil)
        }
        let library = [
            record("boundary", bits: 0xff),       // Eight differing bits: included.
            record("too-far", bits: 0x1ff),       // Nine: excluded, even though linked to boundary.
            record("exact-a", bits: nil, hash: "same"),
            record("no-color", bits: 0, color: nil),
            record("broken", bits: 0, problem: .empty),
            record("close", bits: 1),
            record("recolored", bits: 0, color: 200),
            record("exact-b", bits: 0, hash: "same"),
        ]
        let candidates = [record("near", bits: 0), record("exact", bits: 0, hash: "same"),
                          record("missing", bits: nil), record("unreadable", bits: 0, problem: .empty)]
        let entries = try FolderComparison.compare(library: library, candidates: candidates)
        #expect(entries.map(\.candidate.relativePath) == ["near", "exact", "missing", "unreadable"])
        #expect(entries.map(\.kind) == [.near, .exact, .new, .unreadable])
        #expect(entries[0].matches.map(\.relativePath) == ["boundary", "close", "exact-b"])
        #expect(entries[1].matches.map(\.relativePath) == ["exact-a", "exact-b"])
    }

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
