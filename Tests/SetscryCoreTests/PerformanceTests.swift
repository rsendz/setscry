import Foundation
import MLX
import Testing
@testable import SetscryCore
@testable import SetscryML
@testable import SetscryMLX

/// Opt-in release benchmarks; no wall-clock assertions in the normal test suite.
/// SETSCRY_BENCHMARKS=1 swift test -c release --filter PerformanceTests
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SETSCRY_BENCHMARKS"] == "1"))
struct PerformanceTests {
    private func measure<T>(_ name: String, _ operation: () throws -> T) rethrows -> T {
        let start = ContinuousClock.now
        let result = try operation()
        print("BENCHMARK \(name): \(start.duration(to: .now))")
        return result
    }

    @Test func comparison() throws {
        let library = records(count: 20_000, seed: 1)
        let incoming = records(count: 5_000, seed: 2)
        for _ in 0..<3 {
            let entries = try measure("compare 20,000 library × 5,000 incoming") {
                try FolderComparison.compare(library: library, candidates: incoming)
            }
            #expect(entries.count == incoming.count)
            #expect(entries.allSatisfy { $0.kind == .new })
        }
    }

    @Test func semanticClustering() {
        var generator = Generator(state: 42)
        let embeddings = Dictionary(uniqueKeysWithValues: (0..<3000).map { i in
            (URL(fileURLWithPath: "/images/\(i).jpg"),
             Embedding((0..<512).map { _ in Float(generator.next() % 1000) / 500 - 1 }))
        })
        for _ in 0..<3 {
            let clusters = measure("cluster 3,000 × 512-dimensional vectors") {
                EmbeddingClusterer.cluster(embeddings)
            }
            #expect(clusters.flatMap(\.members).count == 3000)
        }
    }

    @Test func scanAndReadImages() async throws {
        let folder = try ImageFixture.Folder()
        for i in 0..<256 {
            try ImageFixture.writePNG(seed: UInt64(i), size: 512,
                to: folder.url.appendingPathComponent("image-\(i).png"))
        }
        var records: [ImageRecord] = []
        for _ in 0..<3 {
            let start = ContinuousClock.now
            records = try await DatasetScanner().scan(root: folder.url, onProgress: { _ in })
            print("BENCHMARK scan 256 unique 512px PNGs: \(start.duration(to: .now))")
            #expect(records.count == 256)
        }
        let analysis = measure("analyze 256 scanned records") {
            DatasetAnalysis.make(root: folder.url, records: records)
        }
        #expect(analysis.records.count == 256)

        guard MLXRuntime.isAvailable else {
            print("BENCHMARK CLIP unavailable on this host")
            return
        }
        let clip = CLIPEmbedder()
        guard clip.isReady else {
            print("BENCHMARK CLIP weights unavailable; benchmark does not download models")
            return
        }
        let preparation = ContinuousClock.now
        try await clip.prepare()
        print("BENCHMARK prepare CLIP: \(preparation.duration(to: .now))")
        let batchSize = Int(ProcessInfo.processInfo.environment["SETSCRY_BENCHMARK_BATCH"] ?? "32") ?? 32
        try #require(batchSize > 0)
        for _ in 0..<3 {
            let start = ContinuousClock.now
            var count = 0
            for offset in stride(from: 0, to: records.count, by: batchSize) {
                let batch = records[offset..<min(offset + batchSize, records.count)]
                let vectors = try await clip.embed(imagesAt: batch.map(\.url))
                count += vectors.count
            }
            print("BENCHMARK embed 256 uncached images, batch \(batchSize): \(start.duration(to: .now))")
            print("BENCHMARK MLX memory, batch \(batchSize): peak \(Memory.peakMemory), active \(Memory.activeMemory), cache \(Memory.cacheMemory) bytes")
            #expect(count == 256)
        }
    }

    private func records(count: Int, seed: UInt64) -> [ImageRecord] {
        var generator = Generator(state: seed)
        return (0..<count).map { i in
            let path = "image-\(seed)-\(i).jpg"
            return ImageRecord(url: URL(fileURLWithPath: "/images/\(path)"), relativePath: path,
                byteSize: 10_000, modifiedAt: nil, format: "JPEG", pixelSize: nil,
                contentHash: "\(seed)-\(i)", perceptualHash: PerceptualHash(bits: generator.next()),
                colorSignature: ColorSignature(samples: [UInt8](repeating: 128, count: 48)),
                problem: nil, label: nil, split: nil)
        }
    }

    private struct Generator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9e3779b97f4a7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return z ^ (z >> 31)
        }
    }
}
