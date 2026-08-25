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

@Suite("Choosing what to keep")
struct KeeperTests {
    @Test("A name that announces itself as a copy is recognized")
    func copyNames() {
        for name in ["photo copy.jpg", "photo copy 2.jpg", "Copy of photo.jpg", "photo (1).png", "photo (12).png"] {
            #expect(DuplicateFinder.looksLikeACopy(name), "\(name) should read as a copy")
        }
    }

    @Test("Ordinary names, including numbered dataset files, are not copies")
    func originalNames() {
        // The numbered ones matter: a dataset is full of files named this way
        // and none of them are copies of each other.
        for name in ["photo.jpg", "img-2.jpg", "cats 3.png", "0001.png", "copycat.jpg", "(1).png"] {
            #expect(!DuplicateFinder.looksLikeACopy(name), "\(name) should not read as a copy")
        }
    }

    @Test("The original is kept over the copy, whatever order they arrive in")
    func keeperPrefersTheOriginal() async throws {
        let folder = try ImageFixture.Folder()
        let original = try ImageFixture.writePNG(seed: 4, to: folder.url.appendingPathComponent("photo.png"))
        try FileManager.default.copyItem(at: original, to: folder.url.appendingPathComponent("photo copy.png"))

        let records = try await DatasetScanner().scan(root: folder.url) { _ in }
        let analysis = DatasetAnalysis.make(root: folder.url, records: records)

        let group = try #require(analysis.exactDuplicates.first)
        #expect(group.keeper?.fileName == "photo.png")
        #expect(group.redundant.map(\.fileName) == ["photo copy.png"])
    }
}
