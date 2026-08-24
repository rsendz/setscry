//
//  CLIPModelStore.swift
//  Setscry
//
//  Created by Luis Resendez on 08/08/2026.
//

import Foundation

/// Finds the model files, fetching them only if they are not already here.
///
/// A packaged build carries the weights in `Contents/Resources/CLIPModel`, so
/// nothing is ever downloaded. Building from source has no such copy, so the
/// files are fetched once and cached under Application Support. Downloads land
/// in a temporary file and are moved into place only once complete, so an
/// interrupted one cannot leave a half-written checkpoint behind.
public actor CLIPModelStore {
    public struct Progress: Sendable {
        public let file: String
        public let fileIndex: Int
        public let fileCount: Int
        public let bytesReceived: Int64
        public let bytesExpected: Int64

        public var fractionCompleted: Double? {
            guard bytesExpected > 0 else { return nil }
            return min(1, Double(bytesReceived) / Double(bytesExpected))
        }
    }

    public enum Failure: LocalizedError {
        case downloadFailed(String)

        public var errorDescription: String? {
            switch self {
            case .downloadFailed(let file):
                "Couldn't download \(file). Check your connection and try again."
            }
        }
    }

    private let source: CLIPModelSource
    private let session: URLSession

    public init(source: CLIPModelSource) {
        self.source = source
        self.session = URLSession(configuration: .default)
    }

    /// The copy shipped inside the app, if this build has one.
    public nonisolated var bundledDirectory: URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let directory = resources.appendingPathComponent("CLIPModel", isDirectory: true)
        return Self.isComplete(directory) ? directory : nil
    }

    /// Where a source build keeps the files it had to fetch.
    public nonisolated var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Setscry", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(source.identifier, isDirectory: true)
    }

    public nonisolated var directory: URL { bundledDirectory ?? cacheDirectory }

    /// Whether the model can be loaded without fetching anything.
    public nonisolated var isReady: Bool {
        bundledDirectory != nil || Self.isComplete(cacheDirectory)
    }

    private static func isComplete(_ directory: URL) -> Bool {
        CLIPModelSource.bundledFiles.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    /// Returns the model directory, fetching whatever is missing first. Returns
    /// immediately when the app carries the weights, which a packaged build
    /// always does.
    public func download(
        onProgress: @escaping @Sendable (Progress) -> Void = { _ in }
    ) async throws -> URL {
        if let bundledDirectory { return bundledDirectory }

        let directory = cacheDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let files = CLIPModelSource.bundledFiles
        for (index, file) in files.enumerated() {
            let destination = directory.appendingPathComponent(file)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }

            try await download(
                file: file,
                to: destination,
                index: index,
                count: files.count,
                onProgress: onProgress
            )
        }

        return directory
    }

    private func download(
        file: String,
        to destination: URL,
        index: Int,
        count: Int,
        onProgress: @escaping @Sendable (Progress) -> Void
    ) async throws {
        let observer = DownloadObserver { received, expected in
            onProgress(
                Progress(
                    file: file,
                    fileIndex: index,
                    fileCount: count,
                    bytesReceived: received,
                    bytesExpected: expected
                )
            )
        }

        // URLSession writes the body to its own temporary file, which keeps a
        // 600 MB download off the heap entirely.
        let (temporary, response) = try await session.download(
            from: source.downloadURL(for: file),
            delegate: observer
        )

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: temporary)
            throw Failure.downloadFailed(file)
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    /// Deletes files a source build had to fetch. The bundled copy belongs to
    /// the app and is left alone.
    public func removeFromDisk() throws {
        try FileManager.default.removeItem(at: cacheDirectory)
    }
}

/// Relays `URLSession` download progress. `URLSession` calls this on its own
/// queue, so the report closure must be safe to call from anywhere.
private final class DownloadObserver: NSObject, URLSessionDownloadDelegate, Sendable {
    private let report: @Sendable (Int64, Int64) -> Void

    init(report: @escaping @Sendable (Int64, Int64) -> Void) {
        self.report = report
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        report(totalBytesWritten, totalBytesExpectedToWrite)
    }

    /// Required by the protocol; the async `download(from:)` API takes delivery
    /// of the finished file itself.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}
