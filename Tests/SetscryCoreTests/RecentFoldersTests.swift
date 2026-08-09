//
//  RecentFoldersTests.swift
//  Setscry
//
//  Created by Luis Resendez on 09/08/2026.
//

import Foundation
import Testing
@testable import Setscry

@Suite("Recent folders")
struct RecentFoldersTests {
    /// A private suite name keeps these out of the real app's preferences.
    private func makeDefaults() -> UserDefaults {
        let name = "setscry.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Opening a folder puts it at the front, without duplicating it")
    func recordingMovesToFront() throws {
        let defaults = makeDefaults()
        let recents = RecentFolders(defaults: defaults)
        let folder = try ImageFixture.Folder()
        let a = try folder.makeSubfolder("a")
        let b = try folder.makeSubfolder("b")

        _ = recents.recording(a)
        _ = recents.recording(b)
        let result = recents.recording(a)

        #expect(result.first?.lastPathComponent == "a")
        #expect(result.count == 2)
    }

    @Test("Folders that no longer exist are dropped")
    func missingFoldersAreForgotten() throws {
        let defaults = makeDefaults()
        let recents = RecentFolders(defaults: defaults)
        let folder = try ImageFixture.Folder()
        let kept = try folder.makeSubfolder("kept")
        let removed = try folder.makeSubfolder("removed")

        _ = recents.recording(kept)
        _ = recents.recording(removed)
        try FileManager.default.removeItem(at: removed)

        #expect(recents.load().map(\.lastPathComponent) == ["kept"])
    }

    @Test("The list is capped so the menu stays usable")
    func listIsCapped() throws {
        let defaults = makeDefaults()
        let recents = RecentFolders(defaults: defaults)
        let folder = try ImageFixture.Folder()

        for index in 0..<15 {
            _ = recents.recording(try folder.makeSubfolder("folder-\(index)"))
        }

        #expect(recents.load().count == 10)
        #expect(recents.load().first?.lastPathComponent == "folder-14")
    }

    @Test("Clearing empties the list")
    func clearing() throws {
        let defaults = makeDefaults()
        let recents = RecentFolders(defaults: defaults)
        let folder = try ImageFixture.Folder()

        _ = recents.recording(try folder.makeSubfolder("a"))
        recents.clear()

        #expect(recents.load().isEmpty)
    }
}
