//
//  CLIPConfiguration.swift
//  Setscry
//
//  Created by Luis Resendez on 08/08/2026.
//

import Foundation

/// The subset of a Hugging Face `CLIPModel` config that the encoders need.
///
/// Read from the model's own `config.json` rather than hard-coded, so pointing
/// Setscry at a different CLIP checkpoint is a configuration change rather than
/// a code change. That matters in practice: OpenAI's checkpoints use
/// `quick_gelu` while LAION's use `gelu`, and guessing wrong silently degrades
/// every result.
struct CLIPConfiguration: Decodable {
    struct Text: Decodable {
        let hiddenSize: Int
        let numAttentionHeads: Int
        let numHiddenLayers: Int
        let intermediateSize: Int
        let maxPositionEmbeddings: Int
        let vocabSize: Int
        let layerNormEps: Float
        let hiddenAct: String

        enum CodingKeys: String, CodingKey {
            case hiddenSize = "hidden_size"
            case numAttentionHeads = "num_attention_heads"
            case numHiddenLayers = "num_hidden_layers"
            case intermediateSize = "intermediate_size"
            case maxPositionEmbeddings = "max_position_embeddings"
            case vocabSize = "vocab_size"
            case layerNormEps = "layer_norm_eps"
            case hiddenAct = "hidden_act"
        }
    }

    struct Vision: Decodable {
        let hiddenSize: Int
        let numAttentionHeads: Int
        let numHiddenLayers: Int
        let intermediateSize: Int
        let imageSize: Int
        let patchSize: Int
        let layerNormEps: Float
        let hiddenAct: String

        enum CodingKeys: String, CodingKey {
            case hiddenSize = "hidden_size"
            case numAttentionHeads = "num_attention_heads"
            case numHiddenLayers = "num_hidden_layers"
            case intermediateSize = "intermediate_size"
            case imageSize = "image_size"
            case patchSize = "patch_size"
            case layerNormEps = "layer_norm_eps"
            case hiddenAct = "hidden_act"
        }

        var patchCount: Int {
            let side = imageSize / patchSize
            return side * side
        }
    }

    let textConfig: Text
    let visionConfig: Vision
    let projectionDim: Int

    enum CodingKeys: String, CodingKey {
        case textConfig = "text_config"
        case visionConfig = "vision_config"
        case projectionDim = "projection_dim"
    }

    static func load(from url: URL) throws -> CLIPConfiguration {
        try JSONDecoder().decode(CLIPConfiguration.self, from: Data(contentsOf: url))
    }
}

/// How pixels are prepared before they reach the vision encoder, read from
/// `preprocessor_config.json`.
struct CLIPPreprocessorConfiguration: Decodable {
    let imageMean: [Float]
    let imageStd: [Float]

    enum CodingKeys: String, CodingKey {
        case imageMean = "image_mean"
        case imageStd = "image_std"
    }

    /// The values every CLIP checkpoint published so far happens to share, used
    /// when a repository omits the file.
    static let standard = CLIPPreprocessorConfiguration(
        imageMean: [0.48145466, 0.4578275, 0.40821073],
        imageStd: [0.26862954, 0.26130258, 0.27577711]
    )

    static func load(from url: URL) -> CLIPPreprocessorConfiguration {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else {
            return .standard
        }
        return decoded
    }
}
