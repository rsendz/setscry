//
//  SortingTests.swift
//  Setscry
//
//  Created by Luis Resendez on 01/09/2026.
//

import Foundation
import Testing
@testable import SetscryCore

struct SortingTests {
    private func record(
        _ path: String,
        bytes: Int64 = 100,
        pixels: PixelSize? = PixelSize(width: 10, height: 10),
        modified: Date? = Date(timeIntervalSince1970: 1_000)
    ) -> ImageRecord {
        ImageRecord(
            url: URL(fileURLWithPath: "/root/\(path)"),
            relativePath: path,
            byteSize: bytes,
            modifiedAt: modified,
            format: "PNG",
            pixelSize: pixels,
            contentHash: path,
            perceptualHash: nil,
            colorSignature: nil,
            problem: nil,
            label: nil,
            split: nil
        )
    }

    private func key(_ id: String) -> SortKey<ImageRecord> {
        ImageRecord.sortKeys.first { $0.id == id }!
    }

    private func paths(_ records: [ImageRecord]) -> [String] {
        records.map(\.relativePath)
    }

    @Test("An empty filter keeps everything")
    func emptyFilterKeepsEverything() {
        let records = [record("b.png"), record("a.png")]
        let result = Sorting.apply(records, text: "   ", key: nil, isAscending: true)

        #expect(result.count == 2)
    }

    @Test("Filtering matches part of a path, ignoring case and accents")
    func filteringIsForgiving() {
        let records = [record("Holiday/Café.png"), record("work/report.png")]

        #expect(paths(Sorting.apply(records, text: "cafe", key: nil, isAscending: true)) == ["Holiday/Café.png"])
        #expect(paths(Sorting.apply(records, text: "HOLIDAY", key: nil, isAscending: true)) == ["Holiday/Café.png"])
        #expect(Sorting.apply(records, text: "missing", key: nil, isAscending: true).isEmpty)
    }

    @Test("Sorting by size runs both ways")
    func sortingBySize() {
        let records = [record("b.png", bytes: 300), record("a.png", bytes: 100), record("c.png", bytes: 200)]

        #expect(paths(Sorting.apply(records, text: "", key: key("size"), isAscending: true))
            == ["a.png", "c.png", "b.png"])
        #expect(paths(Sorting.apply(records, text: "", key: key("size"), isAscending: false))
            == ["b.png", "c.png", "a.png"])
    }

    /// A file with no dimensions is missing information rather than being the
    /// smallest, so it must not lead the list when the order is reversed.
    @Test("Records with no value sort last whichever way the list points")
    func missingValuesSortLast() {
        let records = [
            record("none.png", pixels: nil),
            record("small.png", pixels: PixelSize(width: 1, height: 1)),
            record("big.png", pixels: PixelSize(width: 100, height: 100)),
        ]

        let up = paths(Sorting.apply(records, text: "", key: key("dimensions"), isAscending: true))
        let down = paths(Sorting.apply(records, text: "", key: key("dimensions"), isAscending: false))

        #expect(up.last == "none.png")
        #expect(down.last == "none.png")
        #expect(up == ["small.png", "big.png", "none.png"])
        #expect(down == ["big.png", "small.png", "none.png"])
    }

    @Test("Equal keys keep a stable order rather than reshuffling")
    func equalKeysAreStable() {
        let records = [record("c.png", bytes: 50), record("a.png", bytes: 50), record("b.png", bytes: 50)]

        let once = paths(Sorting.apply(records, text: "", key: key("size"), isAscending: true))
        let again = paths(Sorting.apply(records.reversed(), text: "", key: key("size"), isAscending: true))

        #expect(once == ["a.png", "b.png", "c.png"])
        #expect(once == again)
    }

    @Test("A group survives the filter when any one member matches")
    func groupsMatchOnAnyMember() {
        let group = DuplicateGroup(
            id: "g1",
            kind: .exact,
            records: [record("holiday/one.png"), record("archive/two.png")]
        )

        #expect(Sorting.apply([group], text: "archive", key: nil, isAscending: true).count == 1)
        #expect(Sorting.apply([group], text: "nowhere", key: nil, isAscending: true).isEmpty)
    }

    /// An exact group is identical by definition, so offering a similarity order
    /// would promise something the data cannot support.
    @Test("Similarity is offered for near duplicates only")
    func similarityKeyIsKindSpecific() {
        #expect(DuplicateGroup.sortKeys(for: .near).contains { $0.id == "similarity" })
        #expect(!DuplicateGroup.sortKeys(for: .exact).contains { $0.id == "similarity" })
    }

    @Test("The problems list does not offer a key its records cannot fill")
    func problemKeysOmitDimensions() {
        #expect(!ImageRecord.problemSortKeys.contains { $0.id == "dimensions" })
        #expect(ImageRecord.problemSortKeys.contains { $0.id == "size" })
    }
}
