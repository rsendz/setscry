//
//  main.swift
//  Setscry
//
//  Created by Luis Resendez on 23/08/2026.
//

import Foundation
import MLX
import SetscryMLX

// Fetches the CLIP checkpoint and writes a copy for Scripts/make-app.sh to put
// inside the app bundle, so a released build never downloads anything.
//
//   swift run -c release prepare-model <output-directory>
//
// The copy is half precision. Setscry casts every weight to float16 the moment
// it loads them, so storing them that way changes no result and halves what the
// app has to ship.

let arguments = Array(CommandLine.arguments.dropFirst())
guard let outputPath = arguments.first else {
    FileHandle.standardError.write(Data("usage: prepare-model <output-directory>\n".utf8))
    exit(2)
}

let output = URL(fileURLWithPath: outputPath)
let source = CLIPModelSource.vitBase32
let store = CLIPModelStore(source: source)

// Small files are copied as they are; only the weights are worth rewriting.
let weightsFile = "model.safetensors"

func report(_ message: String) {
    print(message)
    fflush(stdout)
}

func humanBytes(_ url: URL) -> String {
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.int64Value ?? 0
    return size.formatted(.byteCount(style: .file))
}

/// Progress arrives on URLSession's queue, so the last-reported figure needs a
/// lock rather than a plain variable.
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastPercent = -1

    /// True when this percentage is far enough past the last one to print.
    func shouldReport(_ percent: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard percent >= lastPercent + 10 else { return false }
        lastPercent = percent
        return true
    }
}

report("Fetching \(source.displayName)…")

let throttle = ProgressThrottle()
let directory = try await store.download { progress in
    guard let fraction = progress.fractionCompleted else { return }
    let percent = Int(fraction * 100)
    guard throttle.shouldReport(percent) else { return }
    print("  \(progress.file) \(percent)%")
    fflush(stdout)
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for file in CLIPModelSource.bundledFiles where file != weightsFile {
    let destination = output.appendingPathComponent(file)
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.copyItem(at: directory.appendingPathComponent(file), to: destination)
}

report("Converting weights to half precision…")

var converted: [String: MLXArray] = [:]
for (key, value) in try loadArrays(url: directory.appendingPathComponent(weightsFile)) {
    // Dropped rather than shipped: the model has no matching parameter for
    // either, and loading skips them anyway.
    if key.hasSuffix("position_ids") || key == "logit_scale" { continue }
    converted[key] = value.asType(.float16)
}

let weights = output.appendingPathComponent(weightsFile)
try save(arrays: converted, url: weights)

report("")
report("Wrote \(output.path)")
report("  \(weightsFile): \(humanBytes(directory.appendingPathComponent(weightsFile))) → \(humanBytes(weights))")
