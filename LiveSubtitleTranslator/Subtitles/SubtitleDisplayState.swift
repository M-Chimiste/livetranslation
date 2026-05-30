//
//  SubtitleDisplayState.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import Foundation

struct SubtitleDisplayState: Equatable, Sendable {
    let primaryLine: String
    let secondaryLine: String?
    let isPartial: Bool
    let updatedAt: Date

    init(
        primaryLine: String,
        secondaryLine: String? = nil,
        isPartial: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.primaryLine = primaryLine
        self.secondaryLine = secondaryLine
        self.isPartial = isPartial
        self.updatedAt = updatedAt
    }
}
