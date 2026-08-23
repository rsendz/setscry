//
//  CLIPModelSource.swift
//  Setscry
//
//  Created by Luis Resendez on 08/08/2026.
//

import Foundation

/// Which CLIP checkpoint the app runs, and where to get it if it is missing.
///
/// A packaged build ships the weights inside it, so the download path only runs
/// for someone building from source.
public struct CLIPModelSource: Sendable {
    /// Directory name under Setscry's model cache, and the identifier stored
    /// alongside any vectors this model produces.
    public let identifier: String
    public let displayName: String
    public let repository: String

    /// Everything the model needs to run. All are small except the weights.
    public static let bundledFiles = [
        "config.json",
        "preprocessor_config.json",
        "vocab.json",
        "merges.txt",
        "model.safetensors",
    ]

    public init(
        identifier: String,
        displayName: String,
        repository: String
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.repository = repository
    }

    /// LAION's ViT-B/32, trained on LAION-2B. Small enough to ship inside the
    /// app, and stronger at retrieval than the original OpenAI weights of the
    /// same shape.
    public static let vitBase32 = CLIPModelSource(
        identifier: "clip-vit-b32-laion2b",
        displayName: "CLIP ViT-B/32 (LAION-2B)",
        repository: "laion/CLIP-ViT-B-32-laion2B-s34B-b79K"
    )

    func downloadURL(for file: String) -> URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/main/\(file)")!
    }
}
