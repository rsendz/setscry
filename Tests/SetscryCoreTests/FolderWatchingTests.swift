import Foundation
import Testing
@testable import Setscry

@MainActor
struct FolderWatchingTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<160 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(condition(), "Folder changes should reach the findings")
    }

    @Test("Watching discovers nested additions and removals without leaving the current section")
    func nestedChanges() async throws {
        let folder = try ImageFixture.Folder()
        let model = AppModel()
        defer { model.close() }
        model.open(folder: folder.url)
        try await waitUntil { model.analysis != nil }
        model.selectedSection = .allImages
        let nested = try folder.makeSubfolder("new/arrivals")
        let file = try ImageFixture.writePNG(seed: 7, to: nested.appendingPathComponent("new.png"))
        try await waitUntil { model.analysis?.records.count == 1 }
        #expect(model.selectedSection == .allImages)
        try FileManager.default.removeItem(at: file)
        try await waitUntil { model.analysis?.records.isEmpty == true }
    }

    @Test("A cancelled scan cannot replace a newer folder")
    func switchingFolders() async throws {
        let first = try ImageFixture.Folder()
        let second = try ImageFixture.Folder()
        try ImageFixture.writePNG(seed: 9, to: second.url.appendingPathComponent("second.png"))
        let model = AppModel()
        defer { model.close() }
        model.open(folder: first.url)
        model.open(folder: second.url)
        try await waitUntil { model.analysis?.root == second.url }
        try ImageFixture.writePNG(seed: 10, to: first.url.appendingPathComponent("old.png"))
        try await Task.sleep(for: .seconds(1))
        #expect(model.analysis?.root == second.url)
        #expect(model.analysis?.records.map(\.fileName) == ["second.png"])
    }

    @Test("Pausing watching leaves findings alone, and resuming catches up")
    func pauseAndResume() async throws {
        let folder = try ImageFixture.Folder()
        let model = AppModel()
        defer { model.close() }
        model.open(folder: folder.url)
        try await waitUntil { model.analysis != nil }
        model.watchesFolder = false
        try ImageFixture.writePNG(seed: 11, to: folder.url.appendingPathComponent("arrival.png"))
        try await Task.sleep(for: .seconds(1.5))
        #expect(model.analysis?.records.isEmpty == true)
        model.watchesFolder = true
        try await waitUntil { model.analysis?.records.count == 1 }
    }

    @Test("Replacing an image at the same path updates its fingerprint")
    func replacement() async throws {
        let folder = try ImageFixture.Folder()
        let file = try ImageFixture.writePNG(seed: 12, to: folder.url.appendingPathComponent("image.png"))
        let model = AppModel()
        defer { model.close() }
        model.open(folder: folder.url)
        try await waitUntil { model.analysis != nil }
        let hash = model.analysis?.records.first?.contentHash
        let revision = model.contentRevision
        try ImageFixture.writePNG(seed: 13, to: file)
        try await waitUntil { model.contentRevision > revision }
        #expect(model.analysis?.records.first?.contentHash != hash)
    }

    @Test("A chosen keeper survives a new higher-resolution near duplicate")
    func keeperSurvivesGroupIDChange() async throws {
        let folder = try ImageFixture.Folder()
        try ImageFixture.writePNG(seed: 14, size: 128, to: folder.url.appendingPathComponent("chosen.png"))
        try ImageFixture.writePNG(seed: 14, size: 256, to: folder.url.appendingPathComponent("larger.png"))
        let model = AppModel()
        defer { model.close() }
        model.open(folder: folder.url)
        try await waitUntil { model.analysis != nil }
        let group = try #require(model.analysis?.nearDuplicates.first)
        let chosen = try #require(group.records.first { $0.fileName == "chosen.png" })
        model.chooseKeeper(chosen, in: group)
        try ImageFixture.writePNG(seed: 14, size: 512, to: folder.url.appendingPathComponent("largest.png"))
        try await waitUntil { model.analysis?.records.count == 3 }
        let updated = try #require(model.analysis?.nearDuplicates.first)
        #expect(updated.id != group.id)
        #expect(model.keeper(of: updated)?.url == chosen.url)
    }
}
