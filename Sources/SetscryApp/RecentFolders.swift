//
//  RecentFolders.swift
//  Setscry
//
//  Created by Luis Resendez on 09/08/2026.
//

import Foundation

/// Remembers the last few folders opened.
///
/// Plain paths rather than security-scoped bookmarks: Setscry is not sandboxed,
/// so a path is all that is needed to reopen a folder, and a path is something
/// a person can read in `defaults` if they ever wonder what the app stored.
struct RecentFolders {
    private static let key = "recentFolders"
    private static let limit = 10

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Folders that still exist, newest first.
    func load() -> [URL] {
        let paths = defaults.stringArray(forKey: Self.key) ?? []
        return paths
            .map { URL(fileURLWithPath: $0) }
            .filter { url in
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                return exists && isDirectory.boolValue
            }
    }

    /// Moves `url` to the front, de-duplicating and trimming to the limit.
    ///
    /// De-duplication compares `path`, not the URLs themselves: reading a
    /// directory back with `URL(fileURLWithPath:)` gives it a trailing slash,
    /// so URL equality would treat the folder just opened as a different one
    /// and the menu would fill up with repeats of it.
    func recording(_ url: URL) -> [URL] {
        let path = url.standardizedFileURL.path

        var updated = load().filter { $0.path != path }
        updated.insert(URL(fileURLWithPath: path, isDirectory: true), at: 0)
        updated = Array(updated.prefix(Self.limit))

        defaults.set(updated.map(\.path), forKey: Self.key)
        return updated
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
