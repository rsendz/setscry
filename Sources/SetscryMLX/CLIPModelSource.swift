//
//  CLIPModelSource.swift
//  Setscry
//
//  Created by Luis Resendez on 08/08/2026.
//

import Foundation

/// Where a CLIP checkpoint comes from and what it costs to fetch.
///
/// The download size is stated up front rather than discovered halfway through
/// a scan: a 600 MB download is something the user should agree to knowingly.
public struct CLIPModelSource: Sendable {
    /// Directory name under Setscry's model cache, and the identifier stored
    /// alongside any vectors this model produces.
    public let identifier: String
    public let displayName: String
    public let repository: String
    public let approximateDownloadBytes: Int64

    /// Files fetched from the repository. All are small except the weights.
    static let requiredFiles = [
        "config.json",
        "preprocessor_config.json",
        "vocab.json",
        "merges.txt",
        "model.safetensors",
    ]

    public init(
        identifier: String,
        displayName: String,
        repository: String,
        approximateDownloadBytes: Int64
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.repository = repository
        self.approximateDownloadBytes = approximateDownloadBytes
    }

    /// LAION's ViT-B/32, trained on LAION-2B. A good default: small enough to
    /// download once without ceremony, and stronger at retrieval than the
    /// original OpenAI weights of the same shape.
    public static let vitBase32 = CLIPModelSource(
        identifier: "clip-vit-b32-laion2b",
        displayName: "CLIP ViT-B/32 (LAION-2B)",
        repository: "laion/CLIP-ViT-B-32-laion2B-s34B-b79K",
        approximateDownloadBytes: 606_000_000
    )

    func downloadURL(for file: String) -> URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/main/\(file)")!
    }
}
