//
//  DatasetScanner.swift
//  Setscry
//
//  Created by Luis Resendez on 01/08/2026.
//

import Foundation

/// Walks a folder and produces one ``ImageRecord`` per image file.
///
/// Discovery is a single cheap pass; the expensive per-file work (hashing and
/// decoding) runs concurrently but bounded, so a folder of 100,000 images does
/// not try to open 100,000 file handles at once.
public struct DatasetScanner: Sendable {
    public enum Failure: LocalizedError {
        case notAFolder(URL)

        public var errorDescription: String? {
            switch self {
            case .notAFolder(let url):
                "\(url.lastPathComponent) is not a folder. Drop a folder of images instead."
            }
        }
    }

    public static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "png", "gif", "tif", "tiff",
        "bmp", "heic", "heif", "webp", "avif",
    ]

    public var maxConcurrentReads: Int

    public init(maxConcurrentReads: Int = max(2, ProcessInfo.processInfo.activeProcessorCount)) {
        self.maxConcurrentReads = maxConcurrentReads
    }

    public func scan(
        root: URL,
        onProgress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> [ImageRecord] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw Failure.notAFolder(root)
        }

        let urls = try discoverImageFiles(under: root, onProgress: onProgress)
        return try await readRecords(for: urls, root: root, onProgress: onProgress)
    }

    // MARK: - Discovery

    private func discoverImageFiles(
        under root: URL,
        onProgress: @Sendable (ScanProgress) -> Void
    ) throws -> [URL] {
        onProgress(ScanProgress(phase: .discovering))

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var urls: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            try Task.checkCancellation()

            guard Self.supportedExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }

            urls.append(url)
            if urls.count % 500 == 0 {
                onProgress(ScanProgress(phase: .discovering, processed: urls.count))
            }
        }

        return urls
    }

    // MARK: - Reading

    private func readRecords(
        for urls: [URL],
        root: URL,
        onProgress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> [ImageRecord] {
        let total = urls.count
        guard total > 0 else { return [] }

        var records: [ImageRecord] = []
        records.reserveCapacity(total)

        try await withThrowingTaskGroup(of: ImageRecord.self) { group in
            var next = 0

            func addTask() {
                guard next < total else { return }
                let url = urls[next]
                next += 1
                group.addTask { Self.makeRecord(for: url, root: root) }
            }

            for _ in 0..<Swift.min(maxConcurrentReads, total) { addTask() }

            while let record = try await group.next() {
                try Task.checkCancellation()
                records.append(record)

                // Reporting every file would flood the main actor on large folders.
                if records.count % 8 == 0 || records.count == total {
                    onProgress(
                        ScanProgress(
                            phase: .reading,
                            processed: records.count,
                            total: total,
                            currentFile: record.relativePath
                        )
                    )
                }

                addTask()
            }
        }

        onProgress(ScanProgress(phase: .analyzing, processed: total, total: total))
        return records.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private static func makeRecord(for url: URL, root: URL) -> ImageRecord {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let byteSize = Int64(values?.fileSize ?? 0)
        let attributes = DatasetLayout.attributes(for: url, relativeTo: root)
        let inspection = ImageInspector.inspect(fileAt: url, byteSize: byteSize)

        return ImageRecord(
            url: url,
            relativePath: attributes.relativePath,
            byteSize: byteSize,
            modifiedAt: values?.contentModificationDate,
            format: inspection.format,
            pixelSize: inspection.pixelSize,
            contentHash: try? ContentHasher.sha256(ofFileAt: url),
            perceptualHash: inspection.perceptualHash,
            colorSignature: inspection.colorSignature,
            problem: inspection.problem,
            label: attributes.label,
            split: attributes.split
        )
    }
}
