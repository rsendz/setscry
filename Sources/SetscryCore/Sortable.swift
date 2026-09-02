//
//  Sortable.swift
//  Setscry
//
//  Created by Luis Resendez on 01/09/2026.
//

import Foundation

/// What the shared sort-and-filter control needs from anything it lists.
public protocol Sortable: Identifiable, Sendable {
    /// Matched against the filter text, case- and diacritic-insensitively.
    var filterText: String { get }
    /// Breaks ties, so equal keys never reshuffle between two renders.
    var stableOrder: String { get }
}

/// One way a findings list can be ordered, named for the menu that offers it.
public struct SortKey<Item: Sortable>: Identifiable, Sendable {
    public let id: String
    public let title: String

    /// Whether this item has no value for the key.
    ///
    /// Held apart from the ordering because it must survive reversing: a file
    /// with no dimensions is missing information rather than being the smallest,
    /// so it belongs at the end whichever way the list is pointed. Folding it
    /// into the comparison would send it to the top as soon as the order flipped.
    let isMissing: @Sendable (Item) -> Bool

    /// Ascending order, only ever asked about two items that both have a value.
    let ascending: @Sendable (Item, Item) -> Bool

    /// A key every item can answer.
    public static func required<Value: Comparable>(
        id: String,
        title: String,
        value: @escaping @Sendable (Item) -> Value
    ) -> SortKey<Item> {
        SortKey(id: id, title: title, isMissing: { _ in false }) { a, b in
            value(a) == value(b) ? Sorting.byPath(a, b) : value(a) < value(b)
        }
    }

    /// A key some items have no value for.
    public static func optional<Value: Comparable>(
        id: String,
        title: String,
        value: @escaping @Sendable (Item) -> Value?
    ) -> SortKey<Item> {
        SortKey(id: id, title: title, isMissing: { value($0) == nil }) { a, b in
            guard let first = value(a), let second = value(b) else { return Sorting.byPath(a, b) }
            return first == second ? Sorting.byPath(a, b) : first < second
        }
    }
}

public enum Sorting {
    /// Filters, then sorts.
    ///
    /// That order matters: filtering is one pass and shrinks what has to be
    /// sorted, and on a large folder it is usually what removes most of the work.
    public static func apply<Item: Sortable>(
        _ items: [Item],
        text: String,
        key: SortKey<Item>?,
        isAscending: Bool
    ) -> [Item] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let matched = query.isEmpty ? items : items.filter {
            $0.filterText.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }

        guard let key else { return matched }

        return matched.sorted { a, b in
            let aMissing = key.isMissing(a)
            let bMissing = key.isMissing(b)

            // Missing values sit at the end in both directions.
            if aMissing != bMissing { return bMissing }
            if aMissing { return byPath(a, b) }

            return isAscending ? key.ascending(a, b) : key.ascending(b, a)
        }
    }

    static func byPath<Item: Sortable>(_ a: Item, _ b: Item) -> Bool {
        a.stableOrder.localizedStandardCompare(b.stableOrder) == .orderedAscending
    }
}

// MARK: - Conformances
//
// Each type conforms in the module that owns it: a retroactive conformance from
// the app target on an imported type is a Swift 6 warning.

extension ImageRecord: Sortable {
    public var filterText: String { relativePath }
    public var stableOrder: String { relativePath }

    /// Path, size, dimensions and date. Not format or label: both have few
    /// distinct values, so ordering by them mostly just shuffles.
    public static var sortKeys: [SortKey<ImageRecord>] {
        [
            .required(id: "path", title: "Path", value: \.relativePath),
            .required(id: "size", title: "File size", value: \.byteSize),
            .optional(id: "dimensions", title: "Dimensions", value: { $0.pixelSize?.pixelCount }),
            .optional(id: "modified", title: "Date modified", value: \.modifiedAt),
        ]
    }

    /// Files that would not open have no dimensions, so offering that key in the
    /// problems list would sort by nothing at all.
    public static var problemSortKeys: [SortKey<ImageRecord>] {
        sortKeys.filter { $0.id != "dimensions" }
    }
}

extension DuplicateGroup: Sortable {
    public var filterText: String { records.map(\.relativePath).joined(separator: "\n") }
    public var stableOrder: String { keeper?.relativePath ?? id }

    /// `similarity` only where there is one: an exact group is identical by
    /// definition, and offering the key would promise an order it has not got.
    public static func sortKeys(for kind: Kind) -> [SortKey<DuplicateGroup>] {
        var keys: [SortKey<DuplicateGroup>] = [
            .required(id: "path", title: "Path", value: \.stableOrder),
            .required(id: "count", title: "Number of copies", value: { $0.records.count }),
            .required(id: "reclaimable", title: "Space recoverable", value: \.reclaimableBytes),
        ]

        if kind == .near {
            keys.append(.optional(id: "similarity", title: "Similarity", value: \.spread))
        }

        return keys
    }
}

extension LeakageGroup: Sortable {
    public var filterText: String { records.map(\.relativePath).joined(separator: "\n") }
    public var stableOrder: String { records.first?.relativePath ?? id }

    public static var sortKeys: [SortKey<LeakageGroup>] {
        [
            .required(id: "path", title: "Path", value: \.stableOrder),
            .required(id: "count", title: "Number of copies", value: { $0.records.count }),
            .required(id: "spread", title: "Similarity", value: \.spread),
        ]
    }
}
