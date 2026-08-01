//
//  ImageProblem.swift
//  Setscry
//
//  Created by Luis Resendez on 01/08/2026.
//

import Foundation

/// A deterministic, non-ML defect found while reading a file.
///
/// These are facts rather than suggestions: the file either decoded or it did not.
public enum ImageProblem: Hashable, Sendable {
    /// The file could not be opened or is not recognized as an image.
    case unreadable
    /// The container parsed but the pixel data is incomplete.
    case truncated
    /// The header parsed but the image failed to decode.
    case decodeFailed
    /// The file is zero bytes.
    case empty

    public var summary: String {
        switch self {
        case .unreadable: "Unreadable — not recognized as an image"
        case .truncated: "Truncated — pixel data is incomplete"
        case .decodeFailed: "Corrupt — header parsed but decoding failed"
        case .empty: "Empty — the file contains no data"
        }
    }
}
