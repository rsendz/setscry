//
//  CountedValue.swift
//  Setscry
//
//  Created by Luis Resendez on 01/08/2026.
//

import Foundation

/// A named tally, used for the format, label and split breakdowns.
public struct CountedValue: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }

    /// Tallies a sequence of optional names, ordered by count then name.
    static func tally(_ names: some Sequence<String?>, unknownName: String) -> [CountedValue] {
        var counts: [String: Int] = [:]
        for name in names {
            counts[name ?? unknownName, default: 0] += 1
        }

        return counts
            .map { CountedValue(name: $0.key, count: $0.value) }
            .sorted {
                $0.count == $1.count
                    ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : $0.count > $1.count
            }
    }
}
