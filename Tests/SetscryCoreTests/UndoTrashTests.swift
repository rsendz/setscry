//
//  UndoTrashTests.swift
//  Setscry
//
//  Created by Luis Resendez on 03/09/2026.
//

import Foundation
import Testing
@testable import Setscry
@testable import SetscryCore

/// Trashing files and putting them back.
///
/// A fake trash rather than the real one: a failing run would otherwise leave
/// the fixtures in the tester's own trash for them to find later.
private final class FakeTrash: Trashing, @unchecked Sendable {
    /// Held, not just used: the handle deletes its folder when released, and a
    /// released bin would fail every move for reasons that look like a bug here.
    private let bin: ImageFixture.Folder
    /// Files to refuse to restore, standing in for a trash someone emptied.
    var unrestorable: Set<URL> = []

    init() throws { bin = try ImageFixture.Folder() }

    func trash(_ url: URL) throws -> URL {
        let destination = bin.url.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    func restore(_ trashed: URL, to original: URL) throws {
        if unrestorable.contains(original) {
            try FileManager.default.removeItem(at: trashed)
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.moveItem(at: trashed, to: original)
    }
}

@MainActor
struct UndoTrashTests {
    /// `groupsByEvent` batches registrations per run loop pass, and there is no
    /// run loop here, so undo would silently do nothing without this. `AppModel`
    /// opens its own groups, so registration still works with it off.
    private func makeManager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    /// Trashes and waits, so each test reads as one action.
    private func trashing(_ records: [ImageRecord], in model: AppModel) async {
        await model.moveToTrash(records)
    }

    private func makeModel() throws -> (AppModel, ImageFixture.Folder, FakeTrash) {
        let images = try ImageFixture.Folder()
        let trash = try FakeTrash()

        let model = AppModel(trash: trash)
        model.undoManager = makeManager()
        return (model, images, trash)
    }

    /// Opens the folder for real and waits for the scan, rather than reaching
    /// past `open(folder:)` into the phase it sets.
    private func load(_ model: AppModel, from folder: ImageFixture.Folder) async throws -> DatasetAnalysis {
        model.open(folder: folder.url)

        for _ in 0 ..< 200 {
            if let analysis = model.analysis { return analysis }
            try await Task.sleep(for: .milliseconds(25))
        }

        throw Failure.scanNeverFinished
    }

    private enum Failure: Error { case scanNeverFinished }

    @Test("Undo during a refresh preserves restored findings and redo")
    func undoDuringRefresh() async throws {
        let (model, images, _) = try makeModel()
        defer { model.close() }
        try ImageFixture.writePNG(seed: 40, to: images.url.appendingPathComponent("a.png"))
        try ImageFixture.writePNG(seed: 41, to: images.url.appendingPathComponent("b.png"))
        let before = try await load(model, from: images)
        await model.moveToTrash([try #require(before.records.first)])
        model.rescan()
        await Task.yield()
        model.undoManager?.undo()
        try await Task.sleep(for: .seconds(2))
        #expect(model.analysis?.records == before.records)
        #expect(model.undoManager?.canRedo == true)
    }

    @Test("Trashing removes the files and offers them back")
    func trashingIsUndoable() async throws {
        let (model, images, _) = try makeModel()
        try ImageFixture.writePNG(seed: 1, to: images.url.appendingPathComponent("a.png"))
        try ImageFixture.writePNG(seed: 2, to: images.url.appendingPathComponent("b.png"))

        let before = try await load(model, from: images)
        let doomed = try #require(before.records.first { $0.fileName == "a.png" })

        await trashing([doomed], in: model)

        #expect(model.analysis?.records.count == 1)
        #expect(!FileManager.default.fileExists(atPath: doomed.url.path))
        #expect(model.undoManager?.canUndo == true)
    }

    @Test("Undo puts the file back and restores the findings exactly")
    func undoRestoresTheAnalysis() async throws {
        let (model, images, _) = try makeModel()
        try ImageFixture.writePNG(seed: 1, to: images.url.appendingPathComponent("a.png"))
        try ImageFixture.writePNG(seed: 2, to: images.url.appendingPathComponent("b.png"))

        let before = try await load(model, from: images)
        let doomed = try #require(before.records.first { $0.fileName == "a.png" })

        await trashing([doomed], in: model)
        model.undoManager?.undo()

        #expect(FileManager.default.fileExists(atPath: doomed.url.path))
        // The whole previous analysis comes back rather than being re-derived,
        // so this is an equality check rather than a count.
        #expect(model.analysis == before)
        #expect(model.notice == nil)
    }

    @Test("A file that cannot be put back is reported rather than passed over")
    func undoReportsWhatItCouldNotRestore() async throws {
        let (model, images, trash) = try makeModel()
        try ImageFixture.writePNG(seed: 1, to: images.url.appendingPathComponent("a.png"))
        try ImageFixture.writePNG(seed: 2, to: images.url.appendingPathComponent("b.png"))

        let before = try await load(model, from: images)
        let first = try #require(before.records.first { $0.fileName == "a.png" })
        let second = try #require(before.records.first { $0.fileName == "b.png" })
        trash.unrestorable = [first.url]

        await trashing([first, second], in: model)
        model.undoManager?.undo()

        let notice = try #require(model.notice)
        #expect(notice.contains("Couldn't put 1 file back"))
        #expect(notice.contains("a.png"))
        // The one that did come back is in the findings; the one that did not is not.
        #expect(model.analysis?.records.contains(second) == true)
        #expect(model.analysis?.records.contains(first) == false)
    }

    @Test("Undo does not overwrite a file that reappeared at the same path")
    func undoWillNotClobber() async throws {
        let (model, images, _) = try makeModel()
        let path = images.url.appendingPathComponent("a.png")
        try ImageFixture.writePNG(seed: 1, to: path)
        try ImageFixture.writePNG(seed: 2, to: images.url.appendingPathComponent("b.png"))

        let before = try await load(model, from: images)
        let doomed = try #require(before.records.first { $0.fileName == "a.png" })

        await trashing([doomed], in: model)
        // Something else takes the name back before the undo runs.
        try ImageFixture.writePNG(seed: 99, to: path)
        let replacement = try Data(contentsOf: path)

        model.undoManager?.undo()

        #expect(try Data(contentsOf: path) == replacement)
        #expect(model.notice?.contains("Couldn't put 1 file back") == true)
    }

    @Test("Redo trashes the files again")
    func redoRetrashes() async throws {
        let (model, images, _) = try makeModel()
        try ImageFixture.writePNG(seed: 1, to: images.url.appendingPathComponent("a.png"))
        try ImageFixture.writePNG(seed: 2, to: images.url.appendingPathComponent("b.png"))

        let before = try await load(model, from: images)
        let doomed = try #require(before.records.first { $0.fileName == "a.png" })

        await trashing([doomed], in: model)
        model.undoManager?.undo()
        #expect(FileManager.default.fileExists(atPath: doomed.url.path))

        model.undoManager?.redo()
        // The redo trashes through an async task, so let it run.
        try await Task.sleep(for: .milliseconds(200))

        #expect(!FileManager.default.fileExists(atPath: doomed.url.path))
    }

    @Test("Opening another folder drops the undo history")
    func openingClearsTheStack() async throws {
        let (model, images, _) = try makeModel()
        try ImageFixture.writePNG(seed: 1, to: images.url.appendingPathComponent("a.png"))
        try ImageFixture.writePNG(seed: 2, to: images.url.appendingPathComponent("b.png"))

        let before = try await load(model, from: images)
        let doomed = try #require(before.records.first { $0.fileName == "a.png" })
        await trashing([doomed], in: model)
        #expect(model.undoManager?.canUndo == true)

        let other = try ImageFixture.Folder()
        model.open(folder: other.url)

        // An analysis from the previous folder cannot describe this one.
        #expect(model.undoManager?.canUndo == false)
    }
}
