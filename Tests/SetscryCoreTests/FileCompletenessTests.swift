//
//  FileCompletenessTests.swift
//  Setscry
//
//  Created by Luis Resendez on 28/08/2026.
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import SetscryCore

/// The truncation checks. These exist because `.truncated` was unreachable for
/// two years: ImageIO reports a truncated file as complete and decodes it, so
/// nothing in the decode path can catch this and only a test at the file level
/// will notice if it regresses.
struct FileCompletenessTests {
    private static let formats: [(name: String, type: UTType, ext: String)] = [
        ("JPEG", .jpeg, "jpg"),
        ("PNG", .png, "png"),
        ("GIF", .gif, "gif"),
        ("HEIC", .heic, "heic"),
    ]

    private func verdict(at url: URL) throws -> FileCompleteness.Verdict {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        return FileCompleteness.check(fileAt: url, byteSize: size)
    }

    @Test("A whole file of every checked format reads as complete")
    func wholeFilesAreComplete() throws {
        let folder = try ImageFixture.Folder()

        for format in Self.formats {
            let url = folder.url.appendingPathComponent("whole.\(format.ext)")
            try ImageFixture.writeNoisyImage(seed: 1, type: format.type, to: url)
            #expect(try verdict(at: url) == .complete, "\(format.name) should be complete")
        }
    }

    /// 90% is the case that matters: ImageIO decodes it without complaint and
    /// reports the source complete, so this is exactly the file that used to be
    /// reported as healthy.
    @Test("A truncated file of every checked format is caught", arguments: [0.9, 0.6, 0.33])
    func truncatedFilesAreCaught(fraction: Double) throws {
        let folder = try ImageFixture.Folder()

        for format in Self.formats {
            let url = folder.url.appendingPathComponent("cut.\(format.ext)")
            try ImageFixture.writeNoisyImage(seed: 2, type: format.type, to: url)
            try ImageFixture.truncate(url, to: fraction)
            #expect(try verdict(at: url) == .truncated, "\(format.name) at \(fraction) should be truncated")
        }
    }

    @Test("Padding after the end marker is not damage")
    func trailingPaddingIsAccepted() throws {
        let folder = try ImageFixture.Folder()
        let url = folder.url.appendingPathComponent("padded.jpg")

        try ImageFixture.writeNoisyImage(seed: 3, type: .jpeg, to: url)
        try ImageFixture.appendPadding(16, to: url)

        #expect(try verdict(at: url) == .complete)
    }

    @Test("A format with no cheap end marker is never called truncated")
    func unknownFormatsAreNotAccused() throws {
        let folder = try ImageFixture.Folder()

        let text = folder.url.appendingPathComponent("notes.txt")
        try Data(String(repeating: "setscry ", count: 64).utf8).write(to: text)
        #expect(try verdict(at: text) == .unknown)

        let tiff = folder.url.appendingPathComponent("cut.tiff")
        try ImageFixture.writeNoisyImage(seed: 4, type: .tiff, to: tiff)
        try ImageFixture.truncate(tiff, to: 0.5)
        #expect(try verdict(at: tiff) != .complete)
    }

    @Test("An empty file is not reported as truncated")
    func emptyFileIsUnknown() throws {
        let folder = try ImageFixture.Folder()
        let url = folder.url.appendingPathComponent("empty.jpg")
        try ImageFixture.writeEmptyFile(to: url)

        #expect(FileCompleteness.check(fileAt: url, byteSize: 0) == .unknown)
    }
}

/// The same defect seen through the type the app actually uses.
struct TruncatedInspectionTests {
    private func inspect(_ url: URL) throws -> ImageInspector.Inspection {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        return ImageInspector.inspect(fileAt: url, byteSize: size)
    }

    @Test("A truncated JPEG is reported as truncated, not as healthy")
    func truncatedJPEGIsReported() throws {
        let folder = try ImageFixture.Folder()
        let url = folder.url.appendingPathComponent("cut.jpg")
        try ImageFixture.writeNoisyImage(seed: 5, type: .jpeg, to: url)
        try ImageFixture.truncate(url, to: 0.9)

        let inspection = try inspect(url)
        #expect(inspection.problem == .truncated)
        // A damaged file must not contribute a hash: it would match on the
        // undamaged part and pull whole images into its duplicate group.
        #expect(inspection.perceptualHash == nil)
    }

    /// A truncated GIF cannot even be opened, and used to be reported as "not
    /// recognized as an image", which sends someone looking for the wrong problem.
    @Test("A truncated GIF is reported as truncated rather than unreadable")
    func truncatedGIFIsNotMislabelled() throws {
        let folder = try ImageFixture.Folder()
        let url = folder.url.appendingPathComponent("cut.gif")
        try ImageFixture.writeNoisyImage(seed: 6, type: .gif, to: url)
        try ImageFixture.truncate(url, to: 0.5)

        #expect(try inspect(url).problem == .truncated)
    }

    @Test("A whole image is still reported as healthy")
    func wholeImageIsUnaffected() throws {
        let folder = try ImageFixture.Folder()
        let url = folder.url.appendingPathComponent("whole.jpg")
        try ImageFixture.writeNoisyImage(seed: 7, type: .jpeg, to: url)

        let inspection = try inspect(url)
        #expect(inspection.problem == nil)
        #expect(inspection.perceptualHash != nil)
    }
}
