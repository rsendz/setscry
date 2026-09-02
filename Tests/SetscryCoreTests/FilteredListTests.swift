//
//  FilteredListTests.swift
//  Setscry
//
//  Created by Luis Resendez on 01/09/2026.
//

import Foundation
import Testing
@testable import Setscry
@testable import SetscryCore

@MainActor
struct FilteredListTests {
    private func record(_ path: String, bytes: Int64 = 100) -> ImageRecord {
        ImageRecord(
            url: URL(fileURLWithPath: "/root/\(path)"),
            relativePath: path,
            byteSize: bytes,
            modifiedAt: nil,
            format: "PNG",
            pixelSize: nil,
            contentHash: path,
            perceptualHash: nil,
            colorSignature: nil,
            problem: nil,
            label: nil,
            split: nil
        )
    }

    @Test("A new list is sorted by its first key straight away")
    func startsSorted() {
        let list = FilteredList([record("b.png"), record("a.png")], keys: ImageRecord.sortKeys)

        #expect(list.items.map(\.relativePath) == ["a.png", "b.png"])
    }

    @Test("Filtering narrows the list")
    func filtering() async {
        let list = FilteredList(
            [record("holiday/one.png"), record("work/two.png")],
            keys: ImageRecord.sortKeys
        )

        list.text = "holiday"
        // Awaited directly rather than waiting out the debounce.
        await list.apply()

        #expect(list.items.map(\.relativePath) == ["holiday/one.png"])
    }

    @Test("Changing the key reorders without losing the filter")
    func reorders() async {
        let list = FilteredList(
            [record("a.png", bytes: 300), record("b.png", bytes: 100), record("c.png", bytes: 200)],
            keys: ImageRecord.sortKeys
        )

        list.keyID = "size"
        await list.apply()
        #expect(list.items.map(\.relativePath) == ["b.png", "c.png", "a.png"])

        list.isAscending = false
        await list.apply()
        #expect(list.items.map(\.relativePath) == ["a.png", "c.png", "b.png"])
    }

    /// Trashing a file changes the source without the view being rebuilt, so the
    /// list has to notice on its own.
    @Test("Replacing the source re-applies the current criteria")
    func sourceChangesReapply() async {
        let list = FilteredList([record("a.png"), record("b.png")], keys: ImageRecord.sortKeys)
        list.text = "b"
        await list.apply()
        #expect(list.items.count == 1)

        list.source = [record("b.png"), record("bb.png"), record("c.png")]
        await list.apply()

        #expect(list.items.map(\.relativePath) == ["b.png", "bb.png"])
    }
}
