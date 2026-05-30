//
//  SubtitleStabilizer.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import Foundation

struct SubtitleStabilizer: Equatable, Sendable {
    private(set) var recentFinalSegments: [TranscriptSegment] = []
    private(set) var lastDisplayedText: String?
    private(set) var lastDisplayedWasPartial: Bool?

    var maxContextSegments: Int = 4

    nonisolated init(maxContextSegments: Int = 4) {
        self.maxContextSegments = maxContextSegments
    }

    mutating func shouldDisplay(translatedText: String, isPartial: Bool) -> Bool {
        let normalizedText = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return false }
        guard normalizedText != lastDisplayedText || isPartial != lastDisplayedWasPartial else {
            return false
        }

        lastDisplayedText = normalizedText
        lastDisplayedWasPartial = isPartial
        return true
    }

    mutating func recordFinalSegment(_ segment: TranscriptSegment) {
        recentFinalSegments.append(segment)

        if recentFinalSegments.count > maxContextSegments {
            recentFinalSegments.removeFirst(recentFinalSegments.count - maxContextSegments)
        }
    }

    func context() -> [TranscriptSegment] {
        recentFinalSegments
    }

    mutating func reset() {
        recentFinalSegments.removeAll()
        lastDisplayedText = nil
        lastDisplayedWasPartial = nil
    }
}
