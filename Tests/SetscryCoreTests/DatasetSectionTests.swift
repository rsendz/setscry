//
//  DatasetSectionTests.swift
//  Setscry
//
//  Created by Luis Resendez on 28/08/2026.
//

import Foundation
import Testing
@testable import Setscry

struct DatasetSectionTests {
    /// There is no ⌘10, and `Character("10")` traps rather than failing to
    /// compile, so a tenth section used to crash the app at launch.
    @Test("No more sections get a shortcut than there are digits")
    func shortcutsFitTheDigits() {
        #expect(DatasetSection.shortcutCases.count <= 9)
        #expect(DatasetSection.shortcutCases.allSatisfy { DatasetSection.allCases.contains($0) })
    }

    @Test("Every section is named and explained")
    func everySectionIsDescribed() {
        for section in DatasetSection.allCases {
            #expect(!section.title.isEmpty)
            #expect(!section.summary.isEmpty)
            #expect(!section.systemImage.isEmpty)
        }
    }

    @Test("Browsing is a section, and it flags nothing")
    func browsingIsPresentAndUnbadged() {
        #expect(DatasetSection.allCases.contains(.allImages))
        #expect(DatasetSection.deterministicCases.contains(.allImages))
    }
}
