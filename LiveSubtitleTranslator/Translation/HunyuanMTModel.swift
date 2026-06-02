//
//  HunyuanMTModel.swift
//  LiveSubtitleTranslator
//
//  Minimal from-scratch implementation of Tencent's Hunyuan-MT (hunyuan_v1_dense,
//  1.8B) on core mlx-swift, so it can coexist with FluidAudio/Parakeet (the
//  higher-level mlx-swift-examples package pins swift-transformers <1.1.0 and
//  conflicts). Decoder-only Llama/Qwen-style transformer with GQA, per-head
//  QK-RMSNorm, RoPE, SwiGLU MLP, tied embeddings, 8-bit affine quantization.
//
//  Module property keys are chosen to match the mlx-community/Hy-MT2-1.8B-8bit
//  safetensors weight names so `update(parameters:)` maps cleanly.
//

import Foundation
import MLX
import MLXFast
import MLXNN

enum HunyuanConfig {
    static let hiddenSize = 2048
    static let layerCount = 32
    static let headCount = 16
    static let kvHeadCount = 4
    static let headDim = 128
    static let intermediateSize = 6144
    static let vocabSize = 120_818
    static let rmsNormEps: Float = 1e-5
    static let ropeTheta: Float = 10_000
    static let quantGroupSize = 64
    static let quantBits = 8
    static let eosTokenID = 120_020
    static let bosTokenID = 120_000
}

/// Simple growing key/value cache for autoregressive decoding.
nonisolated final class HunyuanKVCache {
    private(set) var keys: MLXArray?
    private(set) var values: MLXArray?
    private(set) var offset = 0

    nonisolated func update(keys newKeys: MLXArray, values newValues: MLXArray) -> (MLXArray, MLXArray) {
        if let existingKeys = keys, let existingValues = values {
            keys = concatenated([existingKeys, newKeys], axis: 2)
            values = concatenated([existingValues, newValues], axis: 2)
        } else {
            keys = newKeys
            values = newValues
        }
        offset += newKeys.dim(2)
        return (keys!, values!)
    }
}

private nonisolated final class HunyuanAttention: Module {
    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "o_proj") var oProj: Linear
    @ModuleInfo(key: "query_layernorm") var queryNorm: RMSNorm
    @ModuleInfo(key: "key_layernorm") var keyNorm: RMSNorm

    private let rope: RoPE
    private let scale: Float

    nonisolated override init() {
        let h = HunyuanConfig.hiddenSize
        let heads = HunyuanConfig.headCount
        let kvHeads = HunyuanConfig.kvHeadCount
        let dim = HunyuanConfig.headDim
        _qProj.wrappedValue = Linear(h, heads * dim, bias: false)
        _kProj.wrappedValue = Linear(h, kvHeads * dim, bias: false)
        _vProj.wrappedValue = Linear(h, kvHeads * dim, bias: false)
        _oProj.wrappedValue = Linear(heads * dim, h, bias: false)
        _queryNorm.wrappedValue = RMSNorm(dimensions: dim, eps: HunyuanConfig.rmsNormEps)
        _keyNorm.wrappedValue = RMSNorm(dimensions: dim, eps: HunyuanConfig.rmsNormEps)
        rope = RoPE(dimensions: dim, traditional: false, base: HunyuanConfig.ropeTheta)
        scale = pow(Float(dim), -0.5)
        super.init()
    }

    nonisolated func callAsFunction(_ x: MLXArray, mask: MLXArray?, cache: HunyuanKVCache?) -> MLXArray {
        let batch = x.dim(0)
        let length = x.dim(1)
        let heads = HunyuanConfig.headCount
        let kvHeads = HunyuanConfig.kvHeadCount
        let dim = HunyuanConfig.headDim

        // Project, then per-head QK-RMSNorm over the head dimension (Qwen3-style),
        // applied before RoPE.
        var q = queryNorm(qProj(x).reshaped(batch, length, heads, dim))
        var k = keyNorm(kProj(x).reshaped(batch, length, kvHeads, dim))
        var v = vProj(x).reshaped(batch, length, kvHeads, dim)

        q = q.transposed(0, 2, 1, 3)
        k = k.transposed(0, 2, 1, 3)
        v = v.transposed(0, 2, 1, 3)

        let offset = cache?.offset ?? 0
        q = rope(q, offset: offset)
        k = rope(k, offset: offset)

        if let cache {
            (k, v) = cache.update(keys: k, values: v)
        }

        let attended = MLXFast.scaledDotProductAttention(
            queries: q, keys: k, values: v, scale: scale, mask: mask
        )
        let merged = attended.transposed(0, 2, 1, 3).reshaped(batch, length, heads * dim)
        return oProj(merged)
    }
}

private nonisolated final class HunyuanMLP: Module {
    @ModuleInfo(key: "gate_proj") var gateProj: Linear
    @ModuleInfo(key: "up_proj") var upProj: Linear
    @ModuleInfo(key: "down_proj") var downProj: Linear

    nonisolated override init() {
        let h = HunyuanConfig.hiddenSize
        let i = HunyuanConfig.intermediateSize
        _gateProj.wrappedValue = Linear(h, i, bias: false)
        _upProj.wrappedValue = Linear(h, i, bias: false)
        _downProj.wrappedValue = Linear(i, h, bias: false)
        super.init()
    }

    nonisolated func callAsFunction(_ x: MLXArray) -> MLXArray {
        downProj(silu(gateProj(x)) * upProj(x))
    }
}

private nonisolated final class HunyuanDecoderLayer: Module {
    @ModuleInfo(key: "self_attn") var attention: HunyuanAttention
    @ModuleInfo(key: "mlp") var mlp: HunyuanMLP
    @ModuleInfo(key: "input_layernorm") var inputNorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var postAttentionNorm: RMSNorm

    nonisolated override init() {
        _attention.wrappedValue = HunyuanAttention()
        _mlp.wrappedValue = HunyuanMLP()
        _inputNorm.wrappedValue = RMSNorm(dimensions: HunyuanConfig.hiddenSize, eps: HunyuanConfig.rmsNormEps)
        _postAttentionNorm.wrappedValue = RMSNorm(dimensions: HunyuanConfig.hiddenSize, eps: HunyuanConfig.rmsNormEps)
        super.init()
    }

    nonisolated func callAsFunction(_ x: MLXArray, mask: MLXArray?, cache: HunyuanKVCache?) -> MLXArray {
        let h = x + attention(inputNorm(x), mask: mask, cache: cache)
        return h + mlp(postAttentionNorm(h))
    }
}

private nonisolated final class HunyuanInner: Module {
    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    @ModuleInfo(key: "layers") var layers: [HunyuanDecoderLayer]
    @ModuleInfo(key: "norm") var norm: RMSNorm

    nonisolated override init() {
        _embedTokens.wrappedValue = Embedding(
            embeddingCount: HunyuanConfig.vocabSize,
            dimensions: HunyuanConfig.hiddenSize
        )
        _layers.wrappedValue = (0..<HunyuanConfig.layerCount).map { _ in HunyuanDecoderLayer() }
        _norm.wrappedValue = RMSNorm(dimensions: HunyuanConfig.hiddenSize, eps: HunyuanConfig.rmsNormEps)
        super.init()
    }
}

/// Top-level causal LM. Weight keys are prefixed `model.` to match the checkpoint.
nonisolated final class HunyuanForCausalLM: Module {
    @ModuleInfo(key: "model") fileprivate var model: HunyuanInner

    nonisolated override init() {
        _model.wrappedValue = HunyuanInner()
        super.init()
    }

    /// Runs the transformer and returns logits for the final position only.
    nonisolated func callAsFunction(_ tokens: MLXArray, cache: [HunyuanKVCache]) -> MLXArray {
        var h = model.embedTokens(tokens)
        let length = h.dim(1)

        var mask: MLXArray?
        if length > 1 {
            mask = MultiHeadAttention.createAdditiveCausalMask(length).asType(h.dtype)
        }

        for (index, layer) in model.layers.enumerated() {
            h = layer(h, mask: mask, cache: cache[index])
        }
        h = model.norm(h)
        // Tied embeddings: project hidden states back through the embedding matrix.
        return model.embedTokens.asLinear(h)
    }

    nonisolated func newCache() -> [HunyuanKVCache] {
        (0..<HunyuanConfig.layerCount).map { _ in HunyuanKVCache() }
    }
}
