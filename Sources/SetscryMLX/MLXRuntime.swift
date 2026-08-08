//
//  MLXRuntime.swift
//  Setscry
//
//  Created by Luis Resendez on 08/08/2026.
//

import Foundation
import MLX

/// Reports whether MLX can run in this build, and on what.
///
/// MLX needs its Metal kernels compiled into a `.metallib`. Xcode builds
/// produce one; a plain `swift build` does not, because SwiftPM never invokes
/// the Metal compiler. Without it MLX aborts the process from C++ the first
/// time a stream is created — before any Swift error can be thrown, and even
/// when the CPU device is selected. So the check has to happen before MLX is
/// touched at all, which is what this type is for.
public enum MLXRuntime {
    /// Set `SPECIR_MLX_METALLIB` to the path of a compiled `default.metallib`
    /// to use one built elsewhere.
    private static let overrideKey = "SPECIR_MLX_METALLIB"

    public static let metalLibraryURL: URL? = findMetalLibrary()

    /// Whether any MLX work can be attempted. When false, nothing in this
    /// module may call into MLX.
    public static var isAvailable: Bool { metalLibraryURL != nil }

    /// What to tell the user when MLX cannot run, phrased as something they can
    /// act on.
    public static let unavailableReason = """
        This build has no compiled Metal kernels, which MLX needs before it can \
        run. Install them with `xcodebuild -downloadComponent MetalToolchain` \
        and rebuild, or open the package in Xcode, which compiles them as part \
        of the build.
        """

    /// A sentence for the UI describing where the work will run.
    public static var deviceDescription: String {
        isAvailable
            ? "Runs on this Mac's GPU through MLX."
            : "Unavailable in this build."
    }

    /// MLX already defaults to the GPU when its kernels are present, so there
    /// is nothing to select — the only thing that matters is not calling into
    /// MLX at all when they are missing.
    public static func configureDefaultDevice() {}

    private static func findMetalLibrary() -> URL? {
        let fileManager = FileManager.default

        if let override = ProcessInfo.processInfo.environment[overrideKey] {
            let url = URL(fileURLWithPath: override)
            return fileManager.fileExists(atPath: url.path) ? url : nil
        }

        // MLX resolves "colocated" against the binary that contains its own
        // code, which is not always `Bundle.main` — under the test runner they
        // differ. Checking every plausible root keeps this check from
        // disagreeing with MLX and reporting the feature unavailable when it
        // would in fact have loaded.
        var roots: [URL] = []

        if let executable = Bundle.main.executableURL?.deletingLastPathComponent() {
            roots.append(executable)
        }
        roots.append(Bundle.main.bundleURL)
        if let resources = Bundle.main.resourceURL {
            roots.append(resources)
        }

        let owning = Bundle(for: MetalLibraryMarker.self)
        roots.append(owning.bundleURL)
        if let executable = owning.executableURL?.deletingLastPathComponent() {
            roots.append(executable)
        }
        if let resources = owning.resourceURL {
            roots.append(resources)
        }

        if let first = CommandLine.arguments.first {
            roots.append(URL(fileURLWithPath: first).deletingLastPathComponent())
        }

        // The same names, in the same order, that MLX itself tries: a
        // colocated `mlx.metallib` first, then the SwiftPM resource bundle.
        // Checking for something MLX does not look for would report the
        // feature as available and then abort the process.
        let relativePaths = [
            "mlx.metallib",
            "Resources/mlx.metallib",
            "mlx-swift_Cmlx.bundle/default.metallib",
            "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib",
            "Resources/default.metallib",
        ]

        let candidates = roots.flatMap { root in
            relativePaths.map(root.appendingPathComponent)
        }

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }
}

/// Only exists so `Bundle(for:)` can find the bundle this module was linked
/// into, which is where MLX looks for its kernels.
private final class MetalLibraryMarker {}
