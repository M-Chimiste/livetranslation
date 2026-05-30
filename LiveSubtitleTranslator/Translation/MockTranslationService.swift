//
//  MockTranslationService.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import Foundation

struct MockTranslationRequest: Equatable, Sendable {
    let segment: TranscriptSegment
    let context: [TranscriptSegment]
    let targetLanguage: SubtitleLanguage
}

@MainActor
final class MockTranslationService: TranslationService {
    private(set) var requests: [MockTranslationRequest] = []

    func translate(
        segment: TranscriptSegment,
        context: [TranscriptSegment],
        targetLanguage: SubtitleLanguage
    ) async throws -> TranslationSegment {
        requests.append(
            MockTranslationRequest(
                segment: segment,
                context: context,
                targetLanguage: targetLanguage
            )
        )

        return TranslationSegment(
            transcriptID: segment.id,
            sourceText: segment.text,
            translatedText: Self.translation(
                for: segment.text,
                targetLanguage: targetLanguage
            ),
            targetLanguage: targetLanguage
        )
    }

    static func translation(for sourceText: String, targetLanguage: SubtitleLanguage) -> String {
        let normalizedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)

        if targetLanguage == .simplifiedChinese {
            switch normalizedText {
            case "Where are we going tonight?":
                return "我们今晚要去哪里？"
            case "I don't know":
                return "我不知道。"
            case "I don't know, but we need to leave first.":
                return "我不知道，但先离开这里。"
            case "This is not a good idea.":
                return "这不是一个好主意。"
            case "Wait, I hear someone coming.":
                return "等等，我听到有人来了。"
            default:
                return "[模拟翻译] \(normalizedText)"
            }
        }

        if targetLanguage == .traditionalChinese {
            switch normalizedText {
            case "Where are we going tonight?":
                return "我們今晚要去哪裡？"
            case "I don't know":
                return "我不知道。"
            case "I don't know, but we need to leave first.":
                return "我不知道，但先離開這裡。"
            case "This is not a good idea.":
                return "這不是一個好主意。"
            case "Wait, I hear someone coming.":
                return "等等，我聽到有人來了。"
            default:
                return "[模擬翻譯] \(normalizedText)"
            }
        }

        return "[Mock \(targetLanguage.identifier)] \(normalizedText)"
    }
}
