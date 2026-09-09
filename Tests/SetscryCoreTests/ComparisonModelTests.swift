import Foundation
import Testing
@testable import Setscry
@testable import SetscryCore

@MainActor
struct ComparisonModelTests {
    @Test("Comparison publishes results, rejects overlap, and clears stale work")
    func lifecycle() async throws {
        let library = try ImageFixture.Folder()
        let incoming = try ImageFixture.Folder()
        try ImageFixture.writePNG(seed: 25, to: library.url.appendingPathComponent("original.png"))
        try ImageFixture.writePNG(seed: 25, to: incoming.url.appendingPathComponent("copy.png"))
        let records = try await DatasetScanner().scan(root: library.url, onProgress: { _ in })
        let analysis = DatasetAnalysis.make(root: library.url, records: records)
        let model = ComparisonModel()
        model.compare(folder: incoming.url, library: analysis)
        for _ in 0..<100 where model.isRunning { try await Task.sleep(for: .milliseconds(25)) }
        #expect(model.hasResults)
        #expect(model.entries.first?.kind == .exact)
        model.invalidate()
        #expect(!model.hasResults)
        #expect(model.entries.isEmpty)
        #expect(model.message?.contains("library changed") == true)
        model.compare(folder: library.url, library: analysis)
        #expect(!model.isRunning)
        #expect(model.message?.contains("separate folder") == true)
        model.compare(folder: incoming.url, library: analysis)
        model.clear()
        try await Task.sleep(for: .milliseconds(150))
        #expect(!model.hasResults)
        #expect(model.entries.isEmpty)
        #expect(model.folder == nil)
    }
}
