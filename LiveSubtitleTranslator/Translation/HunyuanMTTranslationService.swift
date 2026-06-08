//
//  HunyuanMTTranslationService.swift
//  LiveSubtitleTranslator
//
//  Local translation backend using Tencent Hunyuan-MT2-1.8B (Apache 2.0) run via
//  core mlx-swift on the GPU. Higher quality than NLLB; ~comparable latency on
//  short lines once warm. Decoder-only LLM driven with the model's chat template.
//
//  Model: mlx-community/Hy-MT2-1.8B-8bit (downloaded on first use).
//

import Combine
import Foundation
import Hub
import MLX
import MLXNN
import Tokenizers

enum HunyuanMTError: LocalizedError {
    case unsupportedLanguagePair(source: String, target: String)
    case modelUnavailable
    case noWeightsFound

    var errorDescription: String? {
        switch self {
        case let .unsupportedLanguagePair(source, target):
            "Hunyuan-MT doesn't support \(source) → \(target)."
        case .modelUnavailable:
            "Hunyuan-MT model is not loaded."
        case .noWeightsFound:
            "No Hunyuan-MT model weights were found after download."
        }
    }
}

protocol HunyuanEngine: Sendable {
    func prepare() async throws
    func translate(text: String, sourceLanguage: SubtitleLanguage, targetLanguage: SubtitleLanguage) async throws -> String
}

@MainActor
final class HunyuanMTTranslationService: TranslationService, ObservableObject {
    @Published private(set) var statusMessage: String?
    @Published private(set) var isReady = false
    @Published private(set) var isPreparing = false

    private let engine: HunyuanEngine

    init(engine: HunyuanEngine = LiveHunyuanEngine()) {
        self.engine = engine
    }

    func warmUp() async {
        guard !isReady, !isPreparing else { return }
        isPreparing = true
        statusMessage = "Loading Hunyuan-MT model… (first time downloads ~1.9 GB)"
        do {
            try await engine.prepare()
            isReady = true
            statusMessage = "Ready"
        } catch {
            statusMessage = "Warm-up failed: \(error.localizedDescription)"
        }
        isPreparing = false
    }

    func translate(
        segment: TranscriptSegment,
        context: [TranscriptSegment],
        targetLanguage: SubtitleLanguage
    ) async throws -> TranslationSegment {
        if !isReady { statusMessage = "Loading Hunyuan-MT model…" }
        do {
            let translatedText = try await engine.translate(
                text: segment.text,
                sourceLanguage: SubtitleLanguage(segment.sourceLanguage),
                targetLanguage: targetLanguage
            )
            isReady = true
            statusMessage = "Ready"
            return TranslationSegment(
                transcriptID: segment.id,
                sourceText: segment.text,
                translatedText: translatedText,
                targetLanguage: targetLanguage
            )
        } catch {
            statusMessage = error.localizedDescription
            throw error
        }
    }
}

actor LiveHunyuanEngine: HunyuanEngine {
    private static let repoID = "mlx-community/Hy-MT2-1.8B-8bit"
    private static let maxGeneratedTokens = 128

    private var tokenizer: (any Tokenizer)?
    private var model: HunyuanForCausalLM?

    /// English-language name of a subtitle language for the instruction prompt
    /// (the prompt is written in English). Derived generically from the locale
    /// identifier so any of Hunyuan-MT's supported languages works — no hardcoded
    /// list. Script is handled generically: a Traditional script → "Traditional <X>"
    /// (e.g. zh-Hant → "Traditional Chinese"); the default/Simplified form uses the
    /// base name (e.g. zh-Hans → "Chinese").
    nonisolated static func languageName(for language: SubtitleLanguage) -> String? {
        let english = Locale(identifier: "en_US")
        let components = Locale.Language(identifier: language.identifier)

        guard let code = components.languageCode?.identifier,
              let baseName = english.localizedString(forLanguageCode: code)
        else {
            // Fall back to the full-identifier display name if the code can't be resolved.
            return english.localizedString(forIdentifier: language.identifier)
        }

        switch components.script?.identifier {
        case "Hant":
            return "Traditional \(baseName)"
        default:
            return baseName
        }
    }

    func prepare() async throws {
        guard tokenizer == nil || model == nil else { return }

        let downloadBase = try Self.modelCacheDirectory()
        let hub = HubApi(downloadBase: downloadBase)
        let repoURL = try await hub.snapshot(from: Self.repoID, matching: [])

        let loadedTokenizer = try await AutoTokenizer.from(modelFolder: repoURL, strict: false)

        let builtModel = HunyuanForCausalLM()
        // Match the checkpoint's 8-bit affine quantization before loading weights.
        quantize(model: builtModel, groupSize: HunyuanConfig.quantGroupSize, bits: HunyuanConfig.quantBits)

        let weights = try Self.loadWeights(from: repoURL)
        guard !weights.isEmpty else { throw HunyuanMTError.noWeightsFound }
        let parameters = ModuleParameters.unflattened(weights)
        try builtModel.update(parameters: parameters, verify: .none)
        eval(builtModel)

        tokenizer = loadedTokenizer
        model = builtModel
    }

    func translate(
        text: String,
        sourceLanguage: SubtitleLanguage,
        targetLanguage: SubtitleLanguage
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        guard let targetName = Self.languageName(for: targetLanguage) else {
            throw HunyuanMTError.unsupportedLanguagePair(
                source: sourceLanguage.identifier, target: targetLanguage.identifier
            )
        }

        try await prepare()
        guard let tokenizer, let model else { throw HunyuanMTError.modelUnavailable }

        let instruction = "Translate the following text into \(targetName). Note that you should only output the translated result without any additional explanation:\n\n\(trimmed)"
        let promptTokens = try tokenizer.applyChatTemplate(messages: [["role": "user", "content": instruction]])

        let cache = model.newCache()
        var generated: [Int] = []

        // Prefill.
        var tokensArray = MLXArray(promptTokens.map { Int32($0) }).reshaped([1, promptTokens.count])
        var logits = model(tokensArray, cache: cache)
        var next = Self.argmaxLastToken(logits)

        for _ in 0..<Self.maxGeneratedTokens {
            if next == HunyuanConfig.eosTokenID { break }
            generated.append(next)
            tokensArray = MLXArray([Int32(next)]).reshaped([1, 1])
            logits = model(tokensArray, cache: cache)
            next = Self.argmaxLastToken(logits)
        }

        return tokenizer.decode(tokens: generated, skipSpecialTokens: true)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func argmaxLastToken(_ logits: MLXArray) -> Int {
        let lastIndex = logits.dim(1) - 1
        let lastStep = logits[0, lastIndex]
        let arg = lastStep.argMax(axis: -1)
        arg.eval()
        return arg.item(Int.self)
    }

    private nonisolated static func modelCacheDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return base.appending(path: "LiveSubtitleTranslator/HunyuanModels")
    }

    private nonisolated static func loadWeights(from directory: URL) throws -> [String: MLXArray] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        var merged: [String: MLXArray] = [:]
        for url in contents where url.pathExtension == "safetensors" {
            let arrays = try loadArrays(url: url)
            for (key, value) in arrays { merged[key] = value }
        }
        return merged
    }
}
