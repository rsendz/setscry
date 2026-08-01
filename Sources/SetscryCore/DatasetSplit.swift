//
//  DatasetSplit.swift
//  Setscry
//
//  Created by Luis Resendez on 01/08/2026.
//

import Foundation

/// A train/validation/test split inferred from a folder name.
public enum DatasetSplit: String, CaseIterable, Hashable, Sendable {
    case train
    case validation
    case test

    public var displayName: String {
        switch self {
        case .train: "Train"
        case .validation: "Validation"
        case .test: "Test"
        }
    }

    /// Matches the folder-naming conventions datasets actually ship with.
    static func matching(folderName: String) -> DatasetSplit? {
        switch folderName.lowercased() {
        case "train", "training", "trainval": .train
        case "val", "valid", "validation", "dev": .validation
        case "test", "testing", "eval", "holdout": .test
        default: nil
        }
    }
}
