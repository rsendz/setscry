//
//  VersionTests.swift
//  Setscry
//
//  Created by Luis Resendez on 29/08/2026.
//

import Foundation
import Testing
@testable import SetscryCore

struct VersionTests {
    @Test("The version is two numbers, which is what the plist will carry")
    func versionIsWellFormed() {
        let parts = SetscryVersion.current.split(separator: ".", omittingEmptySubsequences: false)

        #expect(parts.count == 2)
        // A stray space or a "-beta" suffix would be stamped straight into
        // CFBundleShortVersionString, where it is not a version at all.
        #expect(parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) })
    }

    @Test("The displayed version always contains the real one")
    func displayContainsCurrent() {
        #expect(SetscryVersion.display.contains(SetscryVersion.current))
    }

    /// The point of the constant is that the build reads it. If `version.sh`
    /// stops finding it, `make-app.sh` silently stamps something else, so the
    /// agreement is checked rather than assumed.
    @Test("The build script reads the same version this constant holds")
    func scriptAgreesWithSource() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = root.appendingPathComponent("Scripts/version.sh")

        try #require(FileManager.default.fileExists(atPath: script.path))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let printed = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(process.terminationStatus == 0)
        #expect(printed == SetscryVersion.current)
    }
}
