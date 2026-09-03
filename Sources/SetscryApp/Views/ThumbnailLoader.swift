//
//  ThumbnailLoader.swift
//  Setscry
//
//  Created by Luis Resendez on 12/08/2026.
//

import CoreGraphics
import Foundation
import SetscryCore

/// A `CGImage` is immutable and safe to read from any thread, but is not marked
/// `Sendable`. This box states that guarantee explicitly so decoded thumbnails
/// can cross from a background task to the main actor.
struct SendableImage: @unchecked Sendable {
    let cgImage: CGImage
}

/// Decodes thumbnails off the main actor and caches them.
///
/// Grid views ask for hundreds of thumbnails as the user scrolls; decoding on
/// the main actor would stutter, and decoding the same file repeatedly would
/// waste the work.
actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private final class Entry {
        let image: SendableImage
        init(_ image: SendableImage) { self.image = image }
    }

    private let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        // An adaptive grid on a large display shows more than 600 tiles across
        // one scroll burst, and these are small images.
        cache.countLimit = 1200
        return cache
    }()

    func thumbnail(for url: URL, maxPixelSize: Int) async -> SendableImage? {
        // Keyed on the size as well as the file: a 44-point list row and a
        // 132-point grid tile are different images, and keying on the URL alone
        // served whichever was decoded first to both.
        let key = "\(maxPixelSize)|\(url.absoluteString)" as NSString
        if let cached = cache.object(forKey: key) { return cached.image }

        let work = Task.detached(priority: .utility) {
            ImageInspector.thumbnail(forFileAt: url, maxPixelSize: maxPixelSize)
                .map(SendableImage.init)
        }

        // A detached task does not inherit cancellation, and `ThumbnailView`'s
        // `.task(id:)` cancels as soon as a tile scrolls away. Without this a
        // fling through a large grid leaves thousands of decodes running.
        let decoded = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }

        if let decoded { cache.setObject(Entry(decoded), forKey: key) }
        return decoded
    }
}
