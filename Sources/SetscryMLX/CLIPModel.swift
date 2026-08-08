//
//  CLIPModel.swift
//  Setscry
//
//  Created by Luis Resendez on 08/08/2026.
//

import Foundation
import MLX
import MLXNN

/// The text tower: token and position embeddings, a causal transformer, and a
/// pooled output taken at the end-of-text token.
final class CLIPTextModel: Module {
    final class Embeddings: Module {
        @ModuleInfo(key: "token_embedding") var tokenEmbedding: Embedding
        @ModuleInfo(key: "position_embedding") var positionEmbedding: Embedding

        init(vocabularySize: Int, dimensions: Int, maxPositions: Int) {
            self._tokenEmbedding.wrappedValue = Embedding(
                embeddingCount: vocabularySize, dimensions: dimensions
            )
            self._positionEmbedding.wrappedValue = Embedding(
                embeddingCount: maxPositions, dimensions: dimensions
            )
        }

        func callAsFunction(_ tokens: MLXArray) -> MLXArray {
            tokenEmbedding(tokens) + positionEmbedding.weight[..<tokens.dim(1)]
        }
    }

    @ModuleInfo var embeddings: Embeddings
    @ModuleInfo var encoder: CLIPEncoder
    @ModuleInfo(key: "final_layer_norm") var finalLayerNorm: LayerNorm

    init(configuration: CLIPConfiguration.Text) {
        self._embeddings.wrappedValue = Embeddings(
            vocabularySize: configuration.vocabSize,
            dimensions: configuration.hiddenSize,
            maxPositions: configuration.maxPositionEmbeddings
        )
        self._encoder.wrappedValue = CLIPEncoder(
            count: configuration.numHiddenLayers,
            dimensions: configuration.hiddenSize,
            heads: configuration.numAttentionHeads,
            hiddenDimensions: configuration.intermediateSize,
            epsilon: configuration.layerNormEps,
            activation: CLIPActivation(name: configuration.hiddenAct)
        )
        self._finalLayerNorm.wrappedValue = LayerNorm(
            dimensions: configuration.hiddenSize, eps: configuration.layerNormEps
        )
    }

    func callAsFunction(_ tokens: MLXArray) -> MLXArray {
        let (batch, length) = tokens.shape2

        // The end-of-text token has the highest id in the vocabulary, so the
        // position to pool from is simply the argmax of the ids.
        let endPositions = tokens.argMax(axis: -1)

        var x = embeddings(tokens)
        let mask = Self.causalMask(length: length, dtype: x.dtype)
        for layer in encoder.layers {
            x = layer(x, mask: mask)
        }
        x = finalLayerNorm(x)

        return x[MLXArray(0..<Int32(batch)), endPositions]
    }

    /// An additive causal mask whose masked value is finite in the given type.
    ///
    /// `MultiHeadAttention.createAdditiveCausalMask` multiplies by `-1e9`,
    /// which is already infinity in half precision — so the *unmasked* entries
    /// become `0 * infinity`, which is NaN, and every text embedding comes back
    /// NaN. The largest safe magnitude for float16 is what CLIP's own
    /// implementations use here.
    static func causalMask(length: Int, dtype: DType) -> MLXArray {
        let indices = MLXArray(0..<Int32(length))
        let upperTriangle = expandedDimensions(indices, axis: 1) .< expandedDimensions(indices, axis: 0)
        let maskedValue: Float = dtype == .float16 ? -6e4 : -1e9
        return upperTriangle.asType(dtype) * MLXArray(maskedValue).asType(dtype)
    }
}

/// The vision tower: a patch-embedding convolution, a class token, a
/// transformer, and a pooled output taken at the class token.
final class CLIPVisionModel: Module {
    final class Embeddings: Module {
        @ParameterInfo(key: "class_embedding") var classEmbedding: MLXArray
        @ModuleInfo(key: "patch_embedding") var patchEmbedding: Conv2d
        @ModuleInfo(key: "position_embedding") var positionEmbedding: Embedding

        init(configuration: CLIPConfiguration.Vision) {
            self._classEmbedding.wrappedValue = MLXArray.zeros([configuration.hiddenSize])
            self._patchEmbedding.wrappedValue = Conv2d(
                inputChannels: 3,
                outputChannels: configuration.hiddenSize,
                kernelSize: IntOrPair(configuration.patchSize),
                stride: IntOrPair(configuration.patchSize),
                bias: false
            )
            self._positionEmbedding.wrappedValue = Embedding(
                embeddingCount: configuration.patchCount + 1,
                dimensions: configuration.hiddenSize
            )
        }

        func callAsFunction(_ pixels: MLXArray) -> MLXArray {
            let batch = pixels.dim(0)

            // Convolving with stride == kernel is the patchify step; flattening
            // the spatial axes turns the grid into a sequence.
            var patches = patchEmbedding(pixels)
            patches = patches.reshaped(batch, -1, patches.dim(-1))

            let classTokens = broadcast(
                classEmbedding, to: [batch, 1, classEmbedding.dim(0)]
            )

            return concatenated([classTokens, patches], axis: 1) + positionEmbedding.weight
        }
    }

    @ModuleInfo var embeddings: Embeddings
    // Spelled the way the checkpoints spell it, typo included, so the weights
    // load by name.
    @ModuleInfo(key: "pre_layrnorm") var preLayerNorm: LayerNorm
    @ModuleInfo var encoder: CLIPEncoder
    @ModuleInfo(key: "post_layernorm") var postLayerNorm: LayerNorm

    init(configuration: CLIPConfiguration.Vision) {
        self._embeddings.wrappedValue = Embeddings(configuration: configuration)
        self._preLayerNorm.wrappedValue = LayerNorm(
            dimensions: configuration.hiddenSize, eps: configuration.layerNormEps
        )
        self._encoder.wrappedValue = CLIPEncoder(
            count: configuration.numHiddenLayers,
            dimensions: configuration.hiddenSize,
            heads: configuration.numAttentionHeads,
            hiddenDimensions: configuration.intermediateSize,
            epsilon: configuration.layerNormEps,
            activation: CLIPActivation(name: configuration.hiddenAct)
        )
        self._postLayerNorm.wrappedValue = LayerNorm(
            dimensions: configuration.hiddenSize, eps: configuration.layerNormEps
        )
    }

    func callAsFunction(_ pixels: MLXArray) -> MLXArray {
        var x = preLayerNorm(embeddings(pixels))
        for layer in encoder.layers {
            x = layer(x, mask: nil)
        }
        return postLayerNorm(x[0..., 0])
    }
}

/// Both towers plus the projections that put images and text in one shared
/// space — the property that makes searching images by description possible.
final class CLIPModel: Module {
    @ModuleInfo(key: "text_model") var textModel: CLIPTextModel
    @ModuleInfo(key: "vision_model") var visionModel: CLIPVisionModel
    @ModuleInfo(key: "text_projection") var textProjection: Linear
    @ModuleInfo(key: "visual_projection") var visualProjection: Linear

    init(configuration: CLIPConfiguration) {
        self._textModel.wrappedValue = CLIPTextModel(configuration: configuration.textConfig)
        self._visionModel.wrappedValue = CLIPVisionModel(configuration: configuration.visionConfig)
        self._textProjection.wrappedValue = Linear(
            configuration.textConfig.hiddenSize, configuration.projectionDim, bias: false
        )
        self._visualProjection.wrappedValue = Linear(
            configuration.visionConfig.hiddenSize, configuration.projectionDim, bias: false
        )
    }

    func textFeatures(_ tokens: MLXArray) -> MLXArray {
        textProjection(textModel(tokens))
    }

    func imageFeatures(_ pixels: MLXArray) -> MLXArray {
        visualProjection(visionModel(pixels))
    }
}
