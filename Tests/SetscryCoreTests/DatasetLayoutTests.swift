//
//  DatasetLayoutTests.swift
//  Setscry
//
//  Created by Luis Resendez on 04/08/2026.
//

import Foundation
import Testing
@testable import SetscryCore

@Suite("Dataset layout")
struct DatasetLayoutTests {
    private let root = URL(fileURLWithPath: "/datasets/cats")

    @Test("Split and label are read from folder names")
    func splitAndLabel() {
        let attributes = DatasetLayout.attributes(
            for: root.appendingPathComponent("train/tabby/001.jpg"),
            relativeTo: root
        )

        #expect(attributes.split == .train)
        #expect(attributes.label == "tabby")
        #expect(attributes.relativePath == "train/tabby/001.jpg")
    }

    @Test("A label folder alone still yields a label", arguments: [
        ("tabby/001.jpg", "tabby"),
        ("siamese/nested/002.jpg", "nested"),
    ])
    func labelWithoutSplit(path: String, expected: String) {
        let attributes = DatasetLayout.attributes(for: root.appendingPathComponent(path), relativeTo: root)

        #expect(attributes.split == nil)
        #expect(attributes.label == expected)
    }

    @Test("Common split folder spellings are recognized", arguments: [
        ("training", DatasetSplit.train),
        ("val", .validation),
        ("validation", .validation),
        ("testing", .test),
        ("holdout", .test),
    ])
    func splitSpellings(name: String, expected: DatasetSplit) {
        let attributes = DatasetLayout.attributes(
            for: root.appendingPathComponent("\(name)/dog/1.png"),
            relativeTo: root
        )

        #expect(attributes.split == expected)
        #expect(attributes.label == "dog")
    }

    @Test("A file directly in the root has no label or split")
    func bareFile() {
        let attributes = DatasetLayout.attributes(for: root.appendingPathComponent("loose.jpg"), relativeTo: root)

        #expect(attributes.label == nil)
        #expect(attributes.split == nil)
        #expect(attributes.relativePath == "loose.jpg")
    }
}
