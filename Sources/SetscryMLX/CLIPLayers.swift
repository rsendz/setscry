//
//  CLIPLayers.swift
//  Setscry
//
//  Created by Luis Resendez on 08/08/2026.
//

import Foundation
import MLX
import MLXNN

/// The activation used inside the encoder blocks.
///
/// Not cosmetic: OpenAI's CLIP checkpoints were trained with `quick_gelu` and
/// LAION's with `gelu`. Using the wrong one produces plausible-looking but
/// consistently worse embeddings, so it is read from the checkpoint's config.
enum CLIPActivation {
    case gelu
    case quickGELU

    init(name: String) {
        self = name == "quick_gelu" ? .quickGELU : .gelu
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        switch self {
        case .gelu: MLXNN.gelu(x)
        case .quickGELU: x * MLXNN.sigmoid(1.702 * x)
        }
    }
}

/// Multi-head self-attention with CLIP's parameter names.
///
/// MLXNN ships a `MultiHeadAttention`, but it names its projections
/// `query_proj`/`key_proj`/…; CLIP checkpoints use `q_proj`/`k_proj`/`v_proj`.
/// Matching the checkpoint's names means weights load by name with no remapping
/// table to drift out of date.
final class CLIPAttention: Module {
    @ModuleInfo(key: "q_proj") var queryProjection: Linear
    @ModuleInfo(key: "k_proj") var keyProjection: Linear
    @ModuleInfo(key: "v_proj") var valueProjection: Linear
    @ModuleInfo(key: "out_proj") var outputProjection: Linear

    let heads: Int

    init(dimensions: Int, heads: Int) {
        self.heads = heads
        self._queryProjection.wrappedValue = Linear(dimensions, dimensions, bias: true)
        self._keyProjection.wrappedValue = Linear(dimensions, dimensions, bias: true)
        self._valueProjection.wrappedValue = Linear(dimensions, dimensions, bias: true)
        self._outputProjection.wrappedValue = Linear(dimensions, dimensions, bias: true)
    }

    func callAsFunction(_ x: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        let (batch, length, _) = x.shape3

        var queries = queryProjection(x)
        var keys = keyProjection(x)
        var values = valueProjection(x)

        queries = queries.reshaped(batch, length, heads, -1).transposed(0, 2, 1, 3)
        keys = keys.reshaped(batch, length, heads, -1).transposed(0, 2, 1, 3)
        values = values.reshaped(batch, length, heads, -1).transposed(0, 2, 1, 3)

        let scale = sqrt(1 / Float(queries.dim(-1)))
        // The fused kernel avoids materializing the attention-score matrix and
        // uses float32 softmax accumulation for half-precision inputs.
        let maskMode: MLXFast.ScaledDotProductAttentionMaskMode =
            mask.map { .array($0.asType(queries.dtype)) } ?? .none
        let output = MLXFast.scaledDotProductAttention(
            queries: queries, keys: keys, values: values, scale: scale, mask: maskMode
        )
            .transposed(0, 2, 1, 3)
            .reshaped(batch, length, -1)

        return outputProjection(output)
    }
}

final class CLIPMLP: Module {
    @ModuleInfo var fc1: Linear
    @ModuleInfo var fc2: Linear

    let activation: CLIPActivation

    init(dimensions: Int, hiddenDimensions: Int, activation: CLIPActivation) {
        self.activation = activation
        self.fc1 = Linear(dimensions, hiddenDimensions)
        self.fc2 = Linear(hiddenDimensions, dimensions)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        fc2(activation(fc1(x)))
    }
}

/// One pre-norm transformer block, shared by the text and vision towers.
final class CLIPEncoderLayer: Module {
    @ModuleInfo(key: "self_attn") var attention: CLIPAttention
    @ModuleInfo(key: "layer_norm1") var layerNorm1: LayerNorm
    @ModuleInfo(key: "layer_norm2") var layerNorm2: LayerNorm
    @ModuleInfo var mlp: CLIPMLP

    init(dimensions: Int, heads: Int, hiddenDimensions: Int, epsilon: Float, activation: CLIPActivation) {
        self._attention.wrappedValue = CLIPAttention(dimensions: dimensions, heads: heads)
        self._layerNorm1.wrappedValue = LayerNorm(dimensions: dimensions, eps: epsilon)
        self._layerNorm2.wrappedValue = LayerNorm(dimensions: dimensions, eps: epsilon)
        self._mlp.wrappedValue = CLIPMLP(
            dimensions: dimensions,
            hiddenDimensions: hiddenDimensions,
            activation: activation
        )
    }

    func callAsFunction(_ x: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        var x = x + attention(layerNorm1(x), mask: mask)
        x = x + mlp(layerNorm2(x))
        return x
    }
}

/// Wrapper whose only job is to place the layers under the `encoder.layers`
/// key path the checkpoints use.
final class CLIPEncoder: Module {
    @ModuleInfo var layers: [CLIPEncoderLayer]

    init(
        count: Int,
        dimensions: Int,
        heads: Int,
        hiddenDimensions: Int,
        epsilon: Float,
        activation: CLIPActivation
    ) {
        self.layers = (0..<count).map { _ in
            CLIPEncoderLayer(
                dimensions: dimensions,
                heads: heads,
                hiddenDimensions: hiddenDimensions,
                epsilon: epsilon,
                activation: activation
            )
        }
    }
}
