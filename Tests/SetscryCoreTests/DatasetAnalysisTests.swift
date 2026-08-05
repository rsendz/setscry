//
//  DatasetAnalysisTests.swift
//  Setscry
//
//  Created by Luis Resendez on 04/08/2026.
//

import Foundation
import Testing
@testable import SetscryCore

@Suite("Scanning and analysis")
struct DatasetAnalysisTests {
    /// Builds a folder with one of everything Setscry is meant to notice:
    ///
    /// ```
    /// train/cat/original.png      seed 1 @ 256
    /// train/cat/copy.png          byte-identical copy of original
    /// train/cat/resized.png       seed 1 @ 96   → near-duplicate
    /// train/dog/dog1.png          seed 2
    /// train/dog/broken.png        garbage bytes
    /// train/dog/blank.png         zero bytes
    /// test/cat/leaked.png         byte-identical copy of original → leakage
    /// notes.txt                   ignored
    /// ```
    private func makeDataset() throws -> ImageFixture.Folder {
        let folder = try ImageFixture.Folder()

        let cats = try folder.makeSubfolder("train/cat")
        let dogs = try folder.makeSubfolder("train/dog")
        let testCats = try folder.makeSubfolder("test/cat")

        let original = try ImageFixture.writePNG(seed: 1, size: 256, to: cats.appendingPathComponent("original.png"))
        try FileManager.default.copyItem(at: original, to: cats.appendingPathComponent("copy.png"))
        try ImageFixture.writePNG(seed: 1, size: 96, to: cats.appendingPathComponent("resized.png"))

        try ImageFixture.writePNG(seed: 2, size: 256, to: dogs.appendingPathComponent("dog1.png"))
        try ImageFixture.writeCorruptFile(to: dogs.appendingPathComponent("broken.png"))
        try ImageFixture.writeEmptyFile(to: dogs.appendingPathComponent("blank.png"))

        try FileManager.default.copyItem(at: original, to: testCats.appendingPathComponent("leaked.png"))
        try Data("not an image".utf8).write(to: folder.url.appendingPathComponent("notes.txt"))

        return folder
    }

    private func analyze() async throws -> DatasetAnalysis {
        let folder = try makeDataset()
        let records = try await DatasetScanner().scan(root: folder.url) { _ in }
        return DatasetAnalysis.make(root: folder.url, records: records)
    }

    @Test("Only image files are scanned, and labels come along with them")
    func discovery() async throws {
        let analysis = try await analyze()

        #expect(analysis.records.count == 7)
        #expect(!analysis.records.contains { $0.fileName == "notes.txt" })
        #expect(analysis.records.filter { $0.label == "cat" }.count == 4)
        #expect(analysis.records.filter { $0.split == .test }.count == 1)
    }

    @Test("Corrupt and empty files are reported, not silently dropped")
    func corruption() async throws {
        let analysis = try await analyze()
        let problems = analysis.problemImages

        #expect(problems.count == 2)
        #expect(problems.contains { $0.fileName == "broken.png" && $0.problem == .unreadable })
        #expect(problems.contains { $0.fileName == "blank.png" && $0.problem == .empty })
    }

    @Test("Byte-identical files group together")
    func exactDuplicates() async throws {
        let analysis = try await analyze()

        // original.png, copy.png and test/cat/leaked.png are the same bytes.
        #expect(analysis.exactDuplicates.count == 1)
        let group = try #require(analysis.exactDuplicates.first)
        #expect(group.records.count == 3)
        #expect(group.redundant.count == 2)
        #expect(group.reclaimableBytes > 0)
    }

    @Test("A resized copy is reported as a near-duplicate, not an exact one")
    func nearDuplicates() async throws {
        let analysis = try await analyze()

        let group = try #require(analysis.nearDuplicates.first)
        let names = Set(group.records.map(\.fileName))
        #expect(names.contains("resized.png"))
        // The exact-duplicate family collapses to a single representative.
        #expect(group.records.count == 2)
        // The higher-resolution copy is suggested as the one to keep.
        #expect(group.keeper?.fileName != "resized.png")
    }

    @Test("An image in both train and test is flagged once, not once per pairing")
    func leakage() async throws {
        let analysis = try await analyze()

        // original, copy and resized (train) plus leaked (test) are all the same
        // picture, so that is one leaked image rather than three leaked pairs.
        #expect(analysis.leakage.count == 1)
        let group = try #require(analysis.leakage.first)
        #expect(group.splits == [.train, .test])
        #expect(group.records.count == 4)
        // A byte-identical copy sits on both sides, so this is a certainty.
        #expect(group.containsIdenticalFiles)
    }

    @Test("A near-identical, non-identical copy across splits is still leakage but not certain")
    func nearLeakageIsNotReportedAsCertain() async throws {
        let folder = try ImageFixture.Folder()
        let train = try folder.makeSubfolder("train/cat")
        let test = try folder.makeSubfolder("test/cat")
        try ImageFixture.writePNG(seed: 5, size: 256, to: train.appendingPathComponent("a.png"))
        try ImageFixture.writePNG(seed: 5, size: 96, to: test.appendingPathComponent("b.png"))

        let records = try await DatasetScanner().scan(root: folder.url) { _ in }
        let groups = LeakageFinder.groups(in: records)

        #expect(groups.count == 1)
        #expect(groups[0].containsIdenticalFiles == false)
    }

    @Test("The health report totals line up with the records")
    func healthReport() async throws {
        let analysis = try await analyze()
        let health = analysis.health

        #expect(health.totalImages == 7)
        #expect(health.problemCount == 2)
        #expect(health.redundantCopies == 2)
        #expect(health.leakageCount == 1)
        #expect(health.labels.map(\.name) == ["cat", "dog"])
        #expect(health.hasSplits)
        #expect(health.totalBytes > 0)
    }

    @Test("Removing files re-derives the findings without rescanning")
    func removingFiles() async throws {
        let analysis = try await analyze()
        let group = try #require(analysis.exactDuplicates.first)
        let removed = Set(group.redundant.map(\.url))

        let updated = analysis.removing(removed)

        #expect(updated.records.count == analysis.records.count - removed.count)
        #expect(updated.exactDuplicates.isEmpty)
        #expect(updated.health.redundantCopies == 0)
        // The resized copy still straddles the splits, so leakage remains — but
        // it is no longer a byte-identical certainty.
        #expect(updated.leakage.count == 1)
        #expect(updated.leakage[0].containsIdenticalFiles == false)
    }

    @Test("Scanning something that isn't a folder fails clearly")
    func scanningAFile() async throws {
        let folder = try ImageFixture.Folder()
        let file = try ImageFixture.writePNG(seed: 3, to: folder.url.appendingPathComponent("single.png"))

        await #expect(throws: DatasetScanner.Failure.self) {
            try await DatasetScanner().scan(root: file) { _ in }
        }
    }
}
