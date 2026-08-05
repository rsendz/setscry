//
//  DuplicateGroup.swift
//  Setscry
//
//  Created by Luis Resendez on 04/08/2026.
//

import Foundation

/// A set of files Setscry believes are the same image.
public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Byte-identical files. Deterministic, not a judgement call.
        case exact
        /// Visually near-identical files: resized, re-compressed or lightly edited.
        /// Presented as a suggestion for the user to confirm.
        case near
    }

    public let id: String
    public let kind: Kind
    /// Members ordered so the suggested keeper is first.
    public let records: [ImageRecord]
    /// Largest perceptual distance within the group; `nil` for exact groups.
    public let spread: Int?

    public init(id: String, kind: Kind, records: [ImageRecord], spread: Int? = nil) {
        self.id = id
        self.kind = kind
        self.records = records
        self.spread = spread
    }

    public var keeper: ImageRecord? { records.first }

    public var redundant: [ImageRecord] { Array(records.dropFirst()) }

    /// Bytes that would be freed by keeping only the first member.
    public var reclaimableBytes: Int64 {
        redundant.reduce(0) { $0 + $1.byteSize }
    }
}
