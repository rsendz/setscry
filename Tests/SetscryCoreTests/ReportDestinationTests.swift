//
//  ReportDestinationTests.swift
//  Setscry
//
//  Created by Luis Resendez on 04/09/2026.
//

import Foundation
import Testing
@testable import SetscryCore

struct ReportDestinationTests {
    private func analysis() -> DatasetAnalysis {
        DatasetAnalysis.make(root: URL(fileURLWithPath: "/root"), records: [])
    }

    @Test("The extension the user typed picks the format")
    func extensionPicksTheFormat() {
        let csv = ReportExporter.contents(for: URL(fileURLWithPath: "/out/report.csv"), analysis: analysis())
        #expect(csv.hasPrefix("finding,file,group,detail"))

        let html = ReportExporter.contents(for: URL(fileURLWithPath: "/out/report.html"), analysis: analysis())
        #expect(html.contains("<html"))
    }

    /// The lowercasing is real: a save panel will hand back whatever case the
    /// user typed.
    @Test("An upper-case extension is still a spreadsheet")
    func extensionCaseDoesNotMatter() {
        let csv = ReportExporter.contents(for: URL(fileURLWithPath: "/out/report.CSV"), analysis: analysis())

        #expect(csv.hasPrefix("finding,file,group,detail"))
    }

    @Test("Anything else is the page, including no extension at all")
    func htmlIsTheDefault() {
        for name in ["report", "report.html", "report.txt"] {
            let contents = ReportExporter.contents(for: URL(fileURLWithPath: "/out/\(name)"), analysis: analysis())
            #expect(contents.contains("<html"), "\(name) should render as HTML")
        }
    }
}
