//
//  TranslationService.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import Foundation

struct TranslationSegment: Identifiable, Equatable, Sendable {
    let id: UUID
    let transcriptID: UUID
    let sourceText: String
    let translatedText: String
    let targetLanguage: SubtitleLanguage
    let createdAt: Date

    init(
        id: UUID = UUID(),
        transcriptID: UUID,
        sourceText: String,
        translatedText: String,
        targetLanguage: SubtitleLanguage,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.transcriptID = transcriptID
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.targetLanguage = targetLanguage
        self.createdAt = createdAt
    }
}

protocol TranslationService: AnyObject {
    func translate(
        segment: TranscriptSegment,
        context: [TranscriptSegment],
        targetLanguage: SubtitleLanguage
    ) async throws -> TranslationSegment
}
