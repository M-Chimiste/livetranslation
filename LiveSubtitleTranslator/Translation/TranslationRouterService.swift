//
//  TranslationRouterService.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/21/26.
//

import Foundation

@MainActor
final class TranslationRouterService: TranslationService {
    private let settingsStore: SettingsStore
    private let mockTranslationService: TranslationService
    private let appleTranslationService: TranslationService
    private let nllbTranslationService: TranslationService
    private let hunyuanTranslationService: TranslationService

    init(
        settingsStore: SettingsStore,
        mockTranslationService: TranslationService,
        appleTranslationService: TranslationService,
        nllbTranslationService: TranslationService,
        hunyuanTranslationService: TranslationService
    ) {
        self.settingsStore = settingsStore
        self.mockTranslationService = mockTranslationService
        self.appleTranslationService = appleTranslationService
        self.nllbTranslationService = nllbTranslationService
        self.hunyuanTranslationService = hunyuanTranslationService
    }

    func translate(
        segment: TranscriptSegment,
        context: [TranscriptSegment],
        targetLanguage: SubtitleLanguage
    ) async throws -> TranslationSegment {
        switch settingsStore.settings.translationBackend {
        case .mock:
            return try await mockTranslationService.translate(
                segment: segment,
                context: context,
                targetLanguage: targetLanguage
            )
        case .appleTranslation:
            return try await appleTranslationService.translate(
                segment: segment,
                context: context,
                targetLanguage: targetLanguage
            )
        case .localNLLB:
            return try await nllbTranslationService.translate(
                segment: segment,
                context: context,
                targetLanguage: targetLanguage
            )
        case .localHunyuanMT:
            return try await hunyuanTranslationService.translate(
                segment: segment,
                context: context,
                targetLanguage: targetLanguage
            )
        case .remoteLAN:
            throw TranslationServiceError.remoteLANUnavailable
        }
    }
}
