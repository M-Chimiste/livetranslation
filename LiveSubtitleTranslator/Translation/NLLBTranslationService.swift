//
//  NLLBTranslationService.swift
//  LiveSubtitleTranslator
//
//  Local English→Chinese translation backend using NLLB-200-distilled-600M
//  converted to CoreML (community conversion `cstr/nllb-200-coreml-256`,
//  CC-BY-NC — non-commercial use only). Runs on the Apple Neural Engine.
//
//  The model ships as separate encoder/decoder `.mlpackage`s with a SentencePiece
//  (Unigram) tokenizer and is *stateless* (no KV-cache): each decode step re-feeds
//  the full decoder sequence. We download the ~3.2 GB snapshot on first use into
//  Application Support, then greedy-decode. See `NLLBTokenization` for the decode
//  protocol (the pure, unit-tested part).
//

import Combine
import CoreML
import Foundation
import Hub
import Tokenizers

enum NLLBTranslationError: LocalizedError {
    case unsupportedLanguagePair(source: String, target: String)
    case tokenizerMissingLanguageToken(String)
    case modelOutputMissing
    case inferenceFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedLanguagePair(source, target):
            "Local NLLB translation doesn't support \(source) → \(target)."
        case let .tokenizerMissingLanguageToken(code):
            "NLLB tokenizer is missing the language token \"\(code)\"."
        case .modelOutputMissing:
            "NLLB model returned no output."
        case let .inferenceFailed(message):
            "NLLB translation failed: \(message)."
        }
    }
}

/// Seam so the deterministic service wiring can be tested without the model.
protocol NLLBEngine: Sendable {
    func translate(
        text: String,
        sourceLanguage: SubtitleLanguage,
        targetLanguage: SubtitleLanguage
    ) async throws -> String

    /// Download/compile/load the models without translating, so the first real
    /// translation isn't stalled by the one-time load.
    func prepare() async throws
}

@MainActor
final class NLLBTranslationService: TranslationService, ObservableObject {
    /// Short status string for the Settings UI (download / loading state).
    @Published private(set) var statusMessage: String?
    /// True once the model is loaded and a translation has succeeded / warm-up done.
    @Published private(set) var isReady = false
    /// True while warm-up (download/compile/load) is in progress.
    @Published private(set) var isPreparing = false

    private let engine: NLLBEngine

    init(engine: NLLBEngine = LiveNLLBEngine()) {
        self.engine = engine
    }

    /// Eagerly load the model (download/compile/load) so the live loop's first
    /// subtitle is fast. Safe to call repeatedly; no-op once ready or in flight.
    func warmUp() async {
        guard !isReady, !isPreparing else { return }
        isPreparing = true
        statusMessage = "Loading translation model… (first time downloads ~1.7 GB)"
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
        let sourceLanguage = SubtitleLanguage(segment.sourceLanguage)
        if !isReady { statusMessage = "Loading translation model…" }
        do {
            let translatedText = try await engine.translate(
                text: segment.text,
                sourceLanguage: sourceLanguage,
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

/// Real CoreML-backed NLLB engine. Downloads + loads lazily on first translate.
actor LiveNLLBEngine: NLLBEngine {
    // 128-token variant: half the fixed sequence length of the 256 model, so each
    // (stateless) decoder step processes half the positions — ~2× faster per token,
    // which matters for the live translation loop. Subtitle lines fit well within 128.
    private static let repoID = "cstr/nllb-200-coreml-128"
    private static let maxLength = 128
    private static let encoderModelFile = "NLLB_Encoder_128.mlpackage"
    private static let decoderModelFile = "NLLB_Decoder_128.mlpackage"
    /// Cap generated tokens for bounded live-subtitle latency (Chinese renderings of
    /// a single spoken line are short; this prevents a runaway from stalling the loop).
    private static let maxGeneratedTokens = 96

    private var tokenizer: (any Tokenizer)?
    private var encoder: MLModel?
    private var decoder: MLModel?

    func prepare() async throws {
        try await prepareIfNeeded()
    }

    private func prepareIfNeeded() async throws {
        guard tokenizer == nil || encoder == nil || decoder == nil else { return }

        let downloadBase = try Self.modelCacheDirectory()
        let hub = HubApi(downloadBase: downloadBase)
        let repoURL = try await hub.snapshot(from: Self.repoID, matching: [])

        let tokenizerFolder = repoURL.appending(path: "tokenizer")
        // NLLB's `tokenizer_class` ("NllbTokenizer") isn't registered in
        // swift-transformers, so `strict: false` lets it fall back to its BPE
        // implementation — which is correct here: this conversion's tokenizer.json
        // is a BPE model (vocab + merges), the fast NllbTokenizerFast format.
        let loadedTokenizer = try await AutoTokenizer.from(modelFolder: tokenizerFolder, strict: false)

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        let encoderModel = try Self.loadModel(
            at: repoURL.appending(path: Self.encoderModelFile),
            configuration: configuration
        )
        let decoderModel = try Self.loadModel(
            at: repoURL.appending(path: Self.decoderModelFile),
            configuration: configuration
        )

        tokenizer = loadedTokenizer
        encoder = encoderModel
        decoder = decoderModel
    }

    func translate(
        text: String,
        sourceLanguage: SubtitleLanguage,
        targetLanguage: SubtitleLanguage
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        guard let sourceCode = NLLBTokenization.floresCode(for: sourceLanguage),
              let targetCode = NLLBTokenization.floresCode(for: targetLanguage)
        else {
            throw NLLBTranslationError.unsupportedLanguagePair(
                source: sourceLanguage.identifier,
                target: targetLanguage.identifier
            )
        }

        try await prepareIfNeeded()
        guard let tokenizer, let encoder, let decoder else {
            throw NLLBTranslationError.inferenceFailed("models unavailable")
        }

        guard let sourceLanguageID = tokenizer.convertTokenToId(sourceCode) else {
            throw NLLBTranslationError.tokenizerMissingLanguageToken(sourceCode)
        }
        guard let forcedBOSTokenID = tokenizer.convertTokenToId(targetCode) else {
            throw NLLBTranslationError.tokenizerMissingLanguageToken(targetCode)
        }

        let sourceTokenIDs = tokenizer.encode(text: trimmed, addSpecialTokens: false)
        let (inputIDs, attentionMask) = NLLBTokenization.encoderInput(
            sourceTokenIDs: sourceTokenIDs,
            sourceLanguageID: sourceLanguageID,
            maxLength: Self.maxLength
        )

        let inputIDsArray = try Self.int32Array(inputIDs)
        let attentionMaskArray = try Self.int32Array(attentionMask)

        let encoderOutput = try await encoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "input_ids": inputIDsArray,
            "attention_mask": attentionMaskArray
        ]))
        guard let encoderHiddenStates = Self.firstMultiArray(in: encoderOutput) else {
            throw NLLBTranslationError.modelOutputMissing
        }

        var generated = NLLBTokenization.decoderSeed(forcedBOSTokenID: forcedBOSTokenID)

        for _ in 0..<Self.maxGeneratedTokens {
            let decoderInputArray = try Self.int32Array(
                padded(generated, to: Self.maxLength, with: NLLBTokenization.padTokenID)
            )
            let decoderOutput = try await decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                "decoder_input_ids": decoderInputArray,
                "encoder_hidden_states": encoderHiddenStates,
                "encoder_attention_mask": attentionMaskArray
            ]))
            guard let logits = Self.firstMultiArray(in: decoderOutput) else {
                throw NLLBTranslationError.modelOutputMissing
            }

            let nextToken = Self.argmaxRow(in: logits, position: generated.count - 1)
            if nextToken == NLLBTokenization.eosTokenID { break }
            generated.append(nextToken)
        }

        // Drop the [</s>, <target lang code>] seed before detokenizing.
        let outputTokens = Array(generated.dropFirst(2))
        return tokenizer.decode(tokens: outputTokens, skipSpecialTokens: true)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private nonisolated static func modelCacheDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appending(path: "LiveSubtitleTranslator/NLLBModels")
    }

    private nonisolated static func loadModel(at packageURL: URL, configuration: MLModelConfiguration) throws -> MLModel {
        // `.mlpackage` must be compiled to `.mlmodelc` before loading. Compiling a
        // ~800 MB package takes several seconds, so persist the compiled artifact
        // next to the package and reuse it on every subsequent launch.
        if packageURL.pathExtension == "mlmodelc" {
            return try MLModel(contentsOf: packageURL, configuration: configuration)
        }

        let fileManager = FileManager.default
        let cachedCompiledURL = packageURL.deletingPathExtension().appendingPathExtension("mlmodelc")
        if fileManager.fileExists(atPath: cachedCompiledURL.path) {
            return try MLModel(contentsOf: cachedCompiledURL, configuration: configuration)
        }

        let compiledURL = try MLModel.compileModel(at: packageURL)
        do {
            if fileManager.fileExists(atPath: cachedCompiledURL.path) {
                try fileManager.removeItem(at: cachedCompiledURL)
            }
            try fileManager.moveItem(at: compiledURL, to: cachedCompiledURL)
            return try MLModel(contentsOf: cachedCompiledURL, configuration: configuration)
        } catch {
            // If persisting failed, fall back to the freshly compiled temp copy.
            return try MLModel(contentsOf: compiledURL, configuration: configuration)
        }
    }

    private func padded(_ values: [Int], to length: Int, with padValue: Int) -> [Int] {
        guard values.count < length else { return Array(values.prefix(length)) }
        return values + Array(repeating: padValue, count: length - values.count)
    }

    private nonisolated static func int32Array(_ values: [Int]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .int32)
        let pointer = array.dataPointer.bindMemory(to: Int32.self, capacity: values.count)
        for (index, value) in values.enumerated() {
            pointer[index] = Int32(value)
        }
        return array
    }

    /// Reads the model's single output feature positionally — the conversion's
    /// output feature names aren't guaranteed, so we don't hardcode them.
    private nonisolated static func firstMultiArray(in provider: MLFeatureProvider) -> MLMultiArray? {
        for name in provider.featureNames {
            if let value = provider.featureValue(for: name)?.multiArrayValue {
                return value
            }
        }
        return nil
    }

    /// Argmax over the vocabulary dimension of a `[1, seq, vocab]` logits array
    /// at the given sequence `position`, handling float16/float32/double.
    private nonisolated static func argmaxRow(in logits: MLMultiArray, position: Int) -> Int {
        let vocab = logits.shape[2].intValue
        let rowStride = logits.strides[1].intValue
        let elementStride = logits.strides[2].intValue
        let rowOffset = position * rowStride

        var bestIndex = 0
        var bestValue = -Float.greatestFiniteMagnitude

        switch logits.dataType {
        case .float32:
            let pointer = logits.dataPointer.bindMemory(to: Float.self, capacity: logits.count)
            for v in 0..<vocab {
                let value = pointer[rowOffset + v * elementStride]
                if value > bestValue { bestValue = value; bestIndex = v }
            }
        case .float16:
            let pointer = logits.dataPointer.bindMemory(to: Float16.self, capacity: logits.count)
            for v in 0..<vocab {
                let value = Float(pointer[rowOffset + v * elementStride])
                if value > bestValue { bestValue = value; bestIndex = v }
            }
        case .double:
            let pointer = logits.dataPointer.bindMemory(to: Double.self, capacity: logits.count)
            for v in 0..<vocab {
                let value = Float(pointer[rowOffset + v * elementStride])
                if value > bestValue { bestValue = value; bestIndex = v }
            }
        default:
            for v in 0..<vocab {
                let value = logits[[0, NSNumber(value: position), NSNumber(value: v)]].floatValue
                if value > bestValue { bestValue = value; bestIndex = v }
            }
        }

        return bestIndex
    }
}
