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

    private let cache: NSCache<NSURL, Entry> = {
        let cache = NSCache<NSURL, Entry>()
        cache.countLimit = 600
        return cache
    }()

    func thumbnail(for url: URL, maxPixelSize: Int) async -> SendableImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) { return cached.image }

        let decoded = await Task.detached(priority: .utility) {
            ImageInspector.thumbnail(forFileAt: url, maxPixelSize: maxPixelSize)
                .map(SendableImage.init)
        }.value

        if let decoded { cache.setObject(Entry(decoded), forKey: key) }
        return decoded
    }
}
