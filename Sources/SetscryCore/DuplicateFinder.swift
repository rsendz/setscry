//
//  DuplicateFinder.swift
//  Setscry
//
//  Created by Luis Resendez on 04/08/2026.
//

import Foundation

/// Finds byte-identical and visually near-identical images.
public enum DuplicateFinder {
    /// Bits of a 64-bit dHash that may differ before two images are considered
    /// unrelated. Eight is the usual working value: tolerant of resizing and
    /// JPEG re-encoding, tight enough that different photos rarely collide.
    public static let defaultNearThreshold = 8

    // MARK: - Exact

    public static func exactGroups(in records: [ImageRecord]) -> [DuplicateGroup] {
        var byHash: [String: [ImageRecord]] = [:]
        for record in records {
            guard let hash = record.contentHash else { continue }
            byHash[hash, default: []].append(record)
        }

        return byHash
            .filter { $0.value.count > 1 }
            .map { hash, members in
                DuplicateGroup(
                    id: "exact-\(hash)",
                    kind: .exact,
                    records: members.sorted(by: preferredKeeperFirst)
                )
            }
            .sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    // MARK: - Near

    /// Near-duplicate groups, computed over one representative per exact-duplicate
    /// family so byte-identical copies do not swamp the results.
    public static func nearGroups(
        in records: [ImageRecord],
        threshold: Int = defaultNearThreshold
    ) -> [DuplicateGroup] {
        SimilarityClusterer.clusters(of: representatives(of: records), threshold: threshold)
            .map { cluster in
                let members = cluster.sorted(by: highestFidelityFirst)
                return DuplicateGroup(
                    id: "near-\(members[0].relativePath)",
                    kind: .near,
                    records: members,
                    spread: SimilarityClusterer.spread(of: members)
                )
            }
    }

    /// One record per exact-duplicate family, so downstream analyses treat a set
    /// of byte-identical copies as a single image.
    public static func representatives(of records: [ImageRecord]) -> [ImageRecord] {
        var seenHashes = Set<String>()
        var result: [ImageRecord] = []

        for record in records.sorted(by: preferredKeeperFirst) {
            if let hash = record.contentHash {
                guard seenHashes.insert(hash).inserted else { continue }
            }
            result.append(record)
        }

        return result
    }

    // MARK: - Ordering

    /// For identical files, the one whose name does not announce itself as a
    /// copy, then the shallowest, then the alphabetically first.
    ///
    /// The name is the strongest signal available: the bytes are the same, so
    /// nothing else distinguishes them, and "photo.jpg" is almost always the one
    /// someone means to keep over "photo copy 2.jpg".
    private static func preferredKeeperFirst(_ a: ImageRecord, _ b: ImageRecord) -> Bool {
        let copyA = looksLikeACopy(a.fileName)
        let copyB = looksLikeACopy(b.fileName)
        if copyA != copyB { return !copyA }

        let depthA = a.relativePath.split(separator: "/").count
        let depthB = b.relativePath.split(separator: "/").count
        if depthA != depthB { return depthA < depthB }

        return a.relativePath.localizedStandardCompare(b.relativePath) == .orderedAscending
    }

    /// Recognizes the names Finder, browsers and sync tools give a second copy.
    static func looksLikeACopy(_ fileName: String) -> Bool {
        let stem = (fileName as NSString).deletingPathExtension.lowercased()

        // "photo copy", "photo copy 2", "copy of photo"
        if stem.hasSuffix(" copy") || stem.hasPrefix("copy of ") { return true }
        if let range = stem.range(of: " copy "), stem[range.upperBound...].allSatisfy(\.isNumber) {
            return true
        }
        // "photo (1)", the browser and download convention
        if stem.hasSuffix(")"), let open = stem.lastIndex(of: "("), open > stem.startIndex {
            let digits = stem[stem.index(after: open)..<stem.index(before: stem.endIndex)]
            if !digits.isEmpty, digits.allSatisfy(\.isNumber) { return true }
        }

        // Deliberately not "photo-2" or "photo 2": datasets are full of files
        // numbered that way that are nothing to do with copies.
        return false
    }

    /// For near-duplicates the highest-resolution copy is the safest to keep.
    private static func highestFidelityFirst(_ a: ImageRecord, _ b: ImageRecord) -> Bool {
        let pixelsA = a.pixelSize?.pixelCount ?? 0
        let pixelsB = b.pixelSize?.pixelCount ?? 0
        if pixelsA != pixelsB { return pixelsA > pixelsB }
        if a.byteSize != b.byteSize { return a.byteSize > b.byteSize }
        return a.relativePath.localizedStandardCompare(b.relativePath) == .orderedAscending
    }
}
