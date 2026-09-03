//
//  TrashService.swift
//  Setscry
//
//  Created by Luis Resendez on 03/09/2026.
//

import Foundation

/// Moving a file to the trash, and putting it back.
///
/// Behind a protocol so undo can be tested without a test's fixtures ending up
/// in the real trash, where a failing run would leave them for someone to find.
protocol Trashing: Sendable {
    /// Moves `url` to the trash and returns where it landed.
    ///
    /// The destination is the whole point: `FileManager` will hand it over, and
    /// without it a move cannot be offered back.
    func trash(_ url: URL) throws -> URL

    func restore(_ trashed: URL, to original: URL) throws
}

struct SystemTrash: Trashing {
    func trash(_ url: URL) throws -> URL {
        var landed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &landed)

        // Refusing the move rather than losing track of it: a file whose
        // destination is unknown cannot be restored, and reporting it as
        // trashed would promise an undo that cannot work.
        guard let landed = landed as URL? else { throw Failure.destinationUnknown(url) }
        return landed
    }

    func restore(_ trashed: URL, to original: URL) throws {
        try FileManager.default.moveItem(at: trashed, to: original)
    }

    enum Failure: LocalizedError {
        case destinationUnknown(URL)

        var errorDescription: String? {
            switch self {
            case .destinationUnknown(let url):
                "Couldn't tell where \(url.lastPathComponent) went in the trash."
            }
        }
    }
}
