//
//  ScanProgress.swift
//  Setscry
//
//  Created by Luis Resendez on 01/08/2026.
//

import Foundation

/// A snapshot of an in-flight scan.
///
/// The app shows the phase and the file being worked on rather than a bare
/// spinner, so a long scan is legible instead of mysterious.
public struct ScanProgress: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        case discovering
        case reading
        case analyzing

        public var displayName: String {
            switch self {
            case .discovering: "Finding images"
            case .reading: "Reading images"
            case .analyzing: "Analyzing"
            }
        }
    }

    public var phase: Phase
    public var processed: Int
    public var total: Int
    public var currentFile: String?

    public init(phase: Phase, processed: Int = 0, total: Int = 0, currentFile: String? = nil) {
        self.phase = phase
        self.processed = processed
        self.total = total
        self.currentFile = currentFile
    }

    /// `nil` while the total is still unknown, which drives an indeterminate bar.
    public var fractionCompleted: Double? {
        guard total > 0 else { return nil }
        return min(1, Double(processed) / Double(total))
    }
}
