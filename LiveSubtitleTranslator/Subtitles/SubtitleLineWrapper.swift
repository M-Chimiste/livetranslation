//
//  SubtitleLineWrapper.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import Foundation

struct SubtitleLineWrapper: Equatable, Sendable {
    var maxCharsPerLine: Int
    var maxLines: Int

    nonisolated static let `default` = SubtitleLineWrapper(
        maxCharsPerLine: 18,
        maxLines: 2
    )

    nonisolated init(maxCharsPerLine: Int, maxLines: Int) {
        self.maxCharsPerLine = maxCharsPerLine
        self.maxLines = maxLines
    }

    func wrap(_ text: String) -> [String] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty,
              maxCharsPerLine > 0,
              maxLines > 0
        else {
            return []
        }

        var remainingCharacters = Array(trimmedText)
        var lines: [String] = []

        while !remainingCharacters.isEmpty && lines.count < maxLines {
            if remainingCharacters.count <= maxCharsPerLine {
                lines.append(String(remainingCharacters))
                break
            }

            if lines.count == maxLines - 1 {
                let prefixLength = max(0, maxCharsPerLine - 3)
                lines.append(String(remainingCharacters.prefix(prefixLength)) + "...")
                break
            }

            lines.append(String(remainingCharacters.prefix(maxCharsPerLine)))
            remainingCharacters.removeFirst(maxCharsPerLine)
        }

        return lines
    }
}
