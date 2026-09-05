//
//  AppModelTests.swift
//  Setscry
//
//  Created by Luis Resendez on 04/09/2026.
//

import Foundation
import Testing
@testable import Setscry
@testable import SetscryCore

/// The app target had no coverage beyond `RecentFolders`, which is how the
/// phase machine and the keeper logic went untested.
@MainActor
struct AppModelTests {
    /// Refuses every move, to exercise the failure path without touching the
    /// real trash.
    private struct RefusingTrash: Trashing {
        func trash(_ url: URL) throws -> URL { throw CocoaError(.fileWriteNoPermission) }
        func restore(_ trashed: URL, to original: URL) throws {}
    }

    /// Moves files to a temporary folder rather than the real trash, so a run
    /// never leaves fixtures for the tester to clear out by hand.
    private final class MovingTrash: Trashing, @unchecked Sendable {
        private let bin: ImageFixture.Folder

        init() throws { bin = try ImageFixture.Folder() }

        func trash(_ url: URL) throws -> URL {
            let destination = bin.url.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }

        func restore(_ trashed: URL, to original: URL) throws {
            try FileManager.default.moveItem(at: trashed, to: original)
        }
    }

    private enum Failure: Error { case scanNeverFinished }

    private func open(_ model: AppModel, _ folder: ImageFixture.Folder) async throws -> DatasetAnalysis {
        model.open(folder: folder.url)

        for _ in 0 ..< 200 {
            if let analysis = model.analysis { return analysis }
            try await Task.sleep(for: .milliseconds(25))
        }

        throw Failure.scanNeverFinished
    }

    private func folderWithImages(_ names: [String]) throws -> ImageFixture.Folder {
        let folder = try ImageFixture.Folder()
        for (index, name) in names.enumerated() {
            try ImageFixture.writePNG(seed: UInt64(index + 1), to: folder.url.appendingPathComponent(name))
        }
        return folder
    }

    // MARK: - Phases

    @Test("A model with nothing open is idle")
    func startsIdle() {
        let model = AppModel()

        #expect(model.analysis == nil)
        #expect(!model.isScanning)
    }

    @Test("Opening a folder ends in loaded, with the folder's images")
    func openingLoads() async throws {
        let model = AppModel()
        let folder = try folderWithImages(["a.png", "b.png"])

        let analysis = try await open(model, folder)

        #expect(analysis.records.count == 2)
        #expect(!model.isScanning)
        #expect(model.analysis?.root == folder.url)
    }

    @Test("Closing a folder returns to idle")
    func closingReturnsToIdle() async throws {
        let model = AppModel()
        let folder = try folderWithImages(["a.png"])
        _ = try await open(model, folder)

        model.close()

        #expect(model.analysis == nil)
        #expect(!model.isScanning)
    }

    @Test("A folder that is not a folder fails rather than hanging")
    func missingFolderFails() async throws {
        let model = AppModel()
        model.open(folder: URL(fileURLWithPath: "/nowhere/at/all"))

        for _ in 0 ..< 200 where model.isScanning {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(model.analysis == nil)
        #expect(!model.isScanning)
    }

    @Test("Opening another folder clears what belonged to the last one")
    func openingResetsState() async throws {
        let model = AppModel()
        let first = try folderWithImages(["a.png", "b.png"])
        let analysis = try await open(model, first)

        model.notice = "something happened"
        model.inspecting = analysis.records.first
        model.selectedSection = .problems

        let second = try folderWithImages(["c.png"])
        _ = try await open(model, second)

        #expect(model.notice == nil)
        #expect(model.inspecting == nil)
        // Findings from the previous folder say nothing about this one.
        #expect(model.selectedSection == .overview)
    }

    // MARK: - Choosing what to keep

    @Test("A group keeps its own suggestion until the user overrides it")
    func keeperFallsBackToTheSuggestion() async throws {
        let model = AppModel()
        let folder = try ImageFixture.Folder()
        try ImageFixture.writePNG(seed: 1, to: folder.url.appendingPathComponent("original.png"))
        try ImageFixture.writePNG(seed: 1, to: folder.url.appendingPathComponent("copy.png"))

        let analysis = try await open(model, folder)
        let group = try #require(analysis.exactDuplicates.first)

        #expect(model.keeper(of: group) == group.keeper)
        #expect(model.redundant(in: group).count == group.records.count - 1)

        let other = try #require(group.records.last)
        model.chooseKeeper(other, in: group)

        #expect(model.keeper(of: group) == other)
        #expect(model.redundant(in: group).allSatisfy { $0 != other })
    }

    @Test("Keeper choices do not survive opening a different folder")
    func keeperChoicesAreClearedOnOpen() async throws {
        let model = AppModel()
        let folder = try ImageFixture.Folder()
        try ImageFixture.writePNG(seed: 2, to: folder.url.appendingPathComponent("original.png"))
        try ImageFixture.writePNG(seed: 2, to: folder.url.appendingPathComponent("copy.png"))

        let analysis = try await open(model, folder)
        let group = try #require(analysis.exactDuplicates.first)
        model.chooseKeeper(try #require(group.records.last), in: group)

        _ = try await open(model, try folderWithImages(["x.png"]))

        // The choice named a file in a folder that is no longer open.
        #expect(model.keeper(of: group) == group.keeper)
    }

    // MARK: - Findings

    @Test("A file's findings name every check it was caught by")
    func findingsDescribeTheFile() async throws {
        let model = AppModel()
        let folder = try ImageFixture.Folder()
        try ImageFixture.writePNG(seed: 3, to: folder.url.appendingPathComponent("original.png"))
        try ImageFixture.writePNG(seed: 3, to: folder.url.appendingPathComponent("copy.png"))
        try ImageFixture.writeEmptyFile(to: folder.url.appendingPathComponent("broken.png"))

        let analysis = try await open(model, folder)

        let duplicate = try #require(analysis.records.first { $0.fileName == "copy.png" })
        #expect(model.findings(for: duplicate).contains("Has identical copies elsewhere"))

        let broken = try #require(analysis.records.first { $0.fileName == "broken.png" })
        #expect(model.findings(for: broken).contains(ImageProblem.empty.summary))
    }

    // MARK: - Trashing

    @Test("Files that will not move are reported, singular and plural")
    func trashFailuresAreReported() async throws {
        let model = AppModel(trash: RefusingTrash())
        let folder = try folderWithImages(["a.png", "b.png", "c.png", "d.png", "e.png"])
        let analysis = try await open(model, folder)

        await model.moveToTrash([try #require(analysis.records.first)])
        let one = try #require(model.notice)
        #expect(one.contains("Couldn't move 1 file to the trash"))
        #expect(!one.contains("files"))

        await model.moveToTrash(Array(analysis.records.prefix(5)))
        let many = try #require(model.notice)
        #expect(many.contains("Couldn't move 5 files to the trash"))
        // Naming three and counting the rest, rather than dropping them silently.
        #expect(many.contains("and 2 more"))

        // Nothing moved, so nothing may have left the findings.
        #expect(model.analysis?.records.count == 5)
    }

    @Test("Trashing removes the files and re-derives the findings")
    func trashingRederives() async throws {
        let folder = try ImageFixture.Folder()
        try ImageFixture.writePNG(seed: 4, to: folder.url.appendingPathComponent("original.png"))
        try ImageFixture.writePNG(seed: 4, to: folder.url.appendingPathComponent("copy.png"))
        try ImageFixture.writePNG(seed: 5, to: folder.url.appendingPathComponent("other.png"))

        let model = AppModel(trash: try MovingTrash())
        let analysis = try await open(model, folder)
        #expect(analysis.exactDuplicates.count == 1)

        let doomed = try #require(analysis.records.first { $0.fileName == "copy.png" })
        await model.moveToTrash([doomed])

        #expect(model.notice == nil)
        #expect(model.analysis?.records.count == 2)
        // With one copy gone there is no longer a duplicate group at all.
        #expect(model.analysis?.exactDuplicates.isEmpty == true)
    }
}
