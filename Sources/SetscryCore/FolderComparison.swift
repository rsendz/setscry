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
        var entries: [Entry] = []
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
                for (index, record) in usable.enumerated() {
                    if index % 1024 == 0 { try Task.checkCancellation() }
                    guard let other = record.perceptualHash,
                          structure.distance(to: other) <= DuplicateFinder.defaultNearThreshold,
                          let otherColour = record.colorSignature,
                          colour.distance(to: otherColour) <= ColorSignature.maximumMatchingDistance
                    else { continue }
                    matches.append(record)
                }
            }
            entries.append(Entry(candidate: candidate, kind: matches.isEmpty ? .new : .near, matches: matches))
        }
        return entries
    }
}
