//
//  DatasetLayout.swift
//  Setscry
//
//  Created by Luis Resendez on 01/08/2026.
//

import Foundation

/// Derives labels and splits from folder structure alone.
///
/// The convention this understands is the one most image datasets already use:
/// `root/<split>/<label>/image.jpg`, or just `root/<label>/image.jpg`. Anything
/// that does not fit simply produces `nil`, which the UI reports as "unlabeled"
/// rather than guessing.
public enum DatasetLayout {
    public struct Attributes: Hashable, Sendable {
        public let relativePath: String
        public let label: String?
        public let split: DatasetSplit?
    }

    public static func attributes(for url: URL, relativeTo root: URL) -> Attributes {
        let components = relativeComponents(for: url, relativeTo: root)
        let directories = components.dropLast()

        var split: DatasetSplit?
        var labelCandidates: [String] = []

        for directory in directories {
            if let match = DatasetSplit.matching(folderName: directory), split == nil {
                split = match
            } else {
                labelCandidates.append(directory)
            }
        }

        return Attributes(
            relativePath: components.joined(separator: "/"),
            label: labelCandidates.last,
            split: split
        )
    }

    private static func relativeComponents(for url: URL, relativeTo root: URL) -> [String] {
        let fileComponents = url.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents

        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents else {
            return [url.lastPathComponent]
        }

        return Array(fileComponents.dropFirst(rootComponents.count))
    }
}
