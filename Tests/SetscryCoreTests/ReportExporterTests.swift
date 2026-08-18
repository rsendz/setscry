//
//  ReportExporterTests.swift
//  Setscry
//
//  Created by Luis Resendez on 18/08/2026.
//

import Foundation
import Testing
@testable import SetscryCore

@Suite("Report export")
struct ReportExporterTests {
    /// A folder shaped to trip every section at once: a duplicate pair, a file
    /// that won't open, and the same image in two splits.
    private func makeAnalysis() async throws -> (DatasetAnalysis, ImageFixture.Folder) {
        let folder = try ImageFixture.Folder()
        let train = try folder.makeSubfolder("train/cats")
        let test = try folder.makeSubfolder("test/cats")

        let original = try ImageFixture.writePNG(seed: 7, to: train.appendingPathComponent("cat.png"))
        try FileManager.default.copyItem(at: original, to: train.appendingPathComponent("cat copy, edited.png"))
        try FileManager.default.copyItem(at: original, to: test.appendingPathComponent("cat.png"))
        try Data().write(to: train.appendingPathComponent("empty.png"))

        let records = try await DatasetScanner().scan(root: folder.url) { _ in }
        return (DatasetAnalysis.make(root: folder.url, records: records), folder)
    }

    @Test("The CSV lists one row per finding, with commas in filenames quoted")
    func csvContent() async throws {
        let (analysis, _) = try await makeAnalysis()
        let csv = ReportExporter.csv(for: analysis)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false).dropLast()

        #expect(lines.first == "finding,file,group,detail")
        #expect(lines.count > 1)
        #expect(csv.contains("Won't open"))
        #expect(csv.contains("Exact duplicate"))
        #expect(csv.contains("Split leakage"))

        // A path containing a comma has to be quoted or every column after it
        // shifts by one, which is the failure a reader would not notice.
        let quoted = lines.first { $0.contains("cat copy, edited.png") }
        #expect(quoted?.contains("\"train/cats/cat copy, edited.png\"") == true)

        // Every row has to have the same number of columns as the header.
        for line in lines {
            #expect(columnCount(of: String(line)) == 4)
        }
    }

    @Test("The HTML is one self-contained page that escapes what it prints")
    func htmlContent() async throws {
        let (analysis, folder) = try await makeAnalysis()
        try Data().write(to: folder.url.appendingPathComponent("<script>.png"))

        let rescanned = try await DatasetScanner().scan(root: folder.url) { _ in }
        let html = ReportExporter.html(for: DatasetAnalysis.make(root: folder.url, records: rescanned))

        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.hasSuffix("</html>"))
        // Self-contained: nothing to fetch when the file is opened elsewhere.
        #expect(!html.contains("http://"))
        #expect(!html.contains("https://"))
        #expect(!html.contains("<img"))

        #expect(html.contains("Exact duplicates"))
        #expect(html.contains("Split leakage"))

        // A filename is data, not markup, wherever it appears.
        #expect(html.contains("&lt;script&gt;.png"))
        #expect(!html.contains("<script>.png"))
    }

    @Test("A folder with no findings still exports a readable report")
    func emptyAnalysis() async throws {
        let folder = try ImageFixture.Folder()
        try ImageFixture.writePNG(seed: 1, to: folder.url.appendingPathComponent("only.png"))

        let analysis = DatasetAnalysis.make(root: folder.url, records: try await DatasetScanner().scan(root: folder.url) { _ in })

        #expect(ReportExporter.csv(for: analysis) == "finding,file,group,detail\n")

        let html = ReportExporter.html(for: analysis)
        #expect(html.contains("Nothing found."))
        #expect(html.contains("only.png") == false)
    }

    /// Counts CSV columns the way a reader would: commas inside quotes don't
    /// separate anything.
    private func columnCount(of line: String) -> Int {
        var columns = 1
        var insideQuotes = false
        for character in line {
            if character == "\"" { insideQuotes.toggle() }
            if character == ",", !insideQuotes { columns += 1 }
        }
        return columns
    }
}
