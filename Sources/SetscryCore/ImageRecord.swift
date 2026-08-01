//
//  ImageRecord.swift
//  Setscry
//
//  Created by Luis Resendez on 01/08/2026.
//

import Foundation

/// Everything Setscry knows about a single file after the deterministic pass.
///
/// This is the unit every analysis works on. It is a value type with no
/// framework dependencies so analyses stay testable and cheap to pass between
/// tasks.
public struct ImageRecord: Identifiable, Hashable, Sendable {
    public var id: URL { url }

    public let url: URL
    /// Path relative to the scanned root, used everywhere the full path is noise.
    public let relativePath: String
    public let byteSize: Int64
    public let modifiedAt: Date?
    public let format: String?
    public let pixelSize: PixelSize?
    /// SHA-256 of the file's bytes. `nil` when the file could not be read.
    public let contentHash: String?
    public let perceptualHash: PerceptualHash?
    public let colorSignature: ColorSignature?
    public let problem: ImageProblem?
    public let label: String?
    public let split: DatasetSplit?

    public init(
        url: URL,
        relativePath: String,
        byteSize: Int64,
        modifiedAt: Date?,
        format: String?,
        pixelSize: PixelSize?,
        contentHash: String?,
        perceptualHash: PerceptualHash?,
        colorSignature: ColorSignature?,
        problem: ImageProblem?,
        label: String?,
        split: DatasetSplit?
    ) {
        self.url = url
        self.relativePath = relativePath
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
        self.format = format
        self.pixelSize = pixelSize
        self.contentHash = contentHash
        self.perceptualHash = perceptualHash
        self.colorSignature = colorSignature
        self.problem = problem
        self.label = label
        self.split = split
    }

    public var fileName: String { url.lastPathComponent }

    public var isUsable: Bool { problem == nil }
}
