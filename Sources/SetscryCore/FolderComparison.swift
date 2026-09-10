import Foundation

/// Compares incoming images directly with a library, without grouping incoming
/// files together or inferring matches through a chain of similar images.
public enum FolderComparison {
    public enum Kind: String, CaseIterable, Sendable {
        case exact = "Already in library"
        case near = "Possible copies"
        case new = "Not in library"
        case unreadable = "Couldn't compare"
    }

    public struct Entry: Identifiable, Sendable {
        public var id: URL { candidate.url }
        public let candidate: ImageRecord
        public let kind: Kind
        public let matches: [ImageRecord]
    }

    public static func rootsOverlap(_ a: URL, _ b: URL) -> Bool {
        let left = a.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let right = b.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return left.starts(with: right) || right.starts(with: left)
    }

    public static func compare(library: [ImageRecord], candidates: [ImageRecord]) throws -> [Entry] {
        try Task.checkCancellation()
        let usable = library.filter(\.isUsable)
        let byHash = Dictionary(grouping: usable.filter { $0.contentHash != nil }, by: \.contentHash)
        // Keep the hot loop over compact hashes. Walking ImageRecord values for
        // every pair repeatedly retains URLs, strings and arrays that almost
        // every non-match immediately discards.
        let visual = usable.enumerated().compactMap { index, record -> (index: Int, bits: UInt64, color: ColorSignature)? in
            guard let hash = record.perceptualHash, let color = record.colorSignature else { return nil }
            return (index, hash.bits, color)
        }
        let bits = visual.map(\.bits)
        var entries: [Entry] = []
        entries.reserveCapacity(candidates.count)
        for candidate in candidates {
            try Task.checkCancellation()
            guard candidate.isUsable, let hash = candidate.contentHash else {
                entries.append(Entry(candidate: candidate, kind: .unreadable, matches: []))
                continue
            }
            if let matches = byHash[hash], !matches.isEmpty {
                entries.append(Entry(candidate: candidate, kind: .exact, matches: matches))
                continue
            }
            var matches: [ImageRecord] = []
            if let structure = candidate.perceptualHash, let colour = candidate.colorSignature {
                // Cancellation stays responsive without a task lookup per pair.
                for start in stride(from: 0, to: bits.count, by: 1024) {
                    try Task.checkCancellation()
                    for index in start..<min(start + 1024, bits.count)
                    where (structure.bits ^ bits[index]).nonzeroBitCount <= DuplicateFinder.defaultNearThreshold
                        && colour.distance(to: visual[index].color) <= ColorSignature.maximumMatchingDistance {
                        matches.append(usable[visual[index].index])
                    }
                }
            }
            entries.append(Entry(candidate: candidate, kind: matches.isEmpty ? .new : .near, matches: matches))
        }
        return entries
    }
}
