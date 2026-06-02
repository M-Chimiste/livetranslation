//
//  NLLBTokenization.swift
//  LiveSubtitleTranslator
//
//  Pure, dependency-free helpers for the NLLB-200 decoding protocol. Kept
//  separate from the CoreML engine so the token-sequence construction and
//  language mapping can be unit tested without downloading the model.
//
//  NLLB convention (post-2023 fast tokenizer used by the cstr/nllb-200-coreml
//  conversion):
//    - Encoder input = [<src lang code>, <source subword ids…>, </s>] padded to
//      a fixed length with <pad>. attention_mask is 1 for real tokens, 0 for pad.
//    - Decoder is seeded with [</s>, <target lang code>] (NLLB uses </s> as the
//      decoder-start token and forces the target language code as the first
//      generated position), then greedy-decodes until </s>.
//

import Foundation

enum NLLBTokenization {
    /// Special token IDs for this NLLB-200 conversion (verified against the
    /// shipped tokenizer): <s>=0, <pad>=1, </s>=2, <unk>=3.
    static let bosTokenID = 0
    static let padTokenID = 1
    static let eosTokenID = 2
    static let unknownTokenID = 3

    /// Logits/vocabulary dimension of NLLB-200 (output matrix width).
    static let vocabularySize = 256_206

    /// FLORES-200 language code for a subtitle language, or `nil` if the pair
    /// isn't supported by this NLLB path. The engine resolves these strings to
    /// token IDs via the tokenizer rather than hardcoding the numeric IDs.
    nonisolated static func floresCode(for language: SubtitleLanguage) -> String? {
        switch language.identifier {
        case "en":
            return "eng_Latn"
        case "zh-Hans":
            return "zho_Hans"
        case "zh-Hant":
            return "zho_Hant"
        default:
            return nil
        }
    }

    /// Builds the fixed-length encoder input:
    /// `[sourceLanguageID, sourceTokenIDs…, EOS]` right-padded to `maxLength`.
    /// Returns the padded `inputIDs` and the matching `attentionMask`
    /// (1 for real tokens, 0 for padding).
    nonisolated static func encoderInput(
        sourceTokenIDs: [Int],
        sourceLanguageID: Int,
        maxLength: Int,
        eosTokenID: Int = eosTokenID,
        padTokenID: Int = padTokenID
    ) -> (inputIDs: [Int], attentionMask: [Int]) {
        var ids: [Int] = [sourceLanguageID]
        ids.append(contentsOf: sourceTokenIDs)
        ids.append(eosTokenID)

        // Truncate overlong input but always keep the language prefix and a
        // trailing EOS so the model still sees a well-formed sequence.
        if ids.count > maxLength {
            ids = Array(ids.prefix(maxLength - 1)) + [eosTokenID]
        }

        let realTokenCount = ids.count
        if ids.count < maxLength {
            ids.append(contentsOf: Array(repeating: padTokenID, count: maxLength - ids.count))
        }

        let attentionMask = (0..<maxLength).map { $0 < realTokenCount ? 1 : 0 }
        return (ids, attentionMask)
    }

    /// Decoder seed: `[</s>, <target lang code>]`.
    nonisolated static func decoderSeed(forcedBOSTokenID: Int, eosTokenID: Int = eosTokenID) -> [Int] {
        [eosTokenID, forcedBOSTokenID]
    }

    /// Index of the maximum value in a logits row.
    nonisolated static func argmax(_ values: [Float]) -> Int {
        var bestIndex = 0
        var bestValue = -Float.greatestFiniteMagnitude
        for (index, value) in values.enumerated() where value > bestValue {
            bestValue = value
            bestIndex = index
        }
        return bestIndex
    }
}
