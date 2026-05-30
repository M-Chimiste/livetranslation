//
//  AppleTranslationLanguageCatalog.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/22/26.
//

import Combine
import Foundation

@MainActor
final class AppleTranslationLanguageCatalog: ObservableObject {
    @Published private(set) var sourceLanguages: [SubtitleLanguage]
    @Published private(set) var targetLanguages: [SubtitleLanguage]
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?

    private let client: AppleTranslationClient

    init(
        client: AppleTranslationClient,
        initialSourceLanguage: SubtitleLanguage = .english,
        initialTargetLanguage: SubtitleLanguage = .simplifiedChinese
    ) {
        self.client = client
        self.sourceLanguages = Self.sortedLanguages(
            Self.unique([initialSourceLanguage] + SubtitleLanguage.fallbackCases),
            priority: [.english]
        )
        self.targetLanguages = Self.sortedLanguages(
            Self.unique([initialTargetLanguage, .simplifiedChinese, .traditionalChinese]),
            priority: [.simplifiedChinese, .traditionalChinese]
        )
    }

    func refresh(
        sourceLanguage: SubtitleLanguage,
        selectedTargetLanguage: SubtitleLanguage
    ) async -> SubtitleLanguage {
        isLoading = true
        defer { isLoading = false }

        let loadedSourceLanguages = await client.supportedLanguageIdentifiers()
            .map(SubtitleLanguage.init)
        let sourceCandidates = loadedSourceLanguages.isEmpty
            ? SubtitleLanguage.fallbackCases
            : loadedSourceLanguages
        sourceLanguages = Self.sortedLanguages(
            Self.unique([sourceLanguage] + sourceCandidates),
            priority: [.english]
        )

        return await refreshTargets(
            sourceLanguage: sourceLanguage,
            selectedTargetLanguage: selectedTargetLanguage
        )
    }

    func refreshTargets(
        sourceLanguage: SubtitleLanguage,
        selectedTargetLanguage: SubtitleLanguage
    ) async -> SubtitleLanguage {
        let targetCandidates = sourceLanguages.filter {
            !Self.languagesAreEquivalent($0, sourceLanguage)
        }
        var supportedTargets: [SubtitleLanguage] = []

        for candidate in targetCandidates {
            let status = await client.availabilityStatus(
                from: sourceLanguage.identifier,
                to: candidate.identifier
            )
            if status == .installed || status == .supported {
                supportedTargets.append(candidate)
            }
        }

        let hasSupportedTargets = !supportedTargets.isEmpty
        let visibleTargets = hasSupportedTargets
            ? supportedTargets
            : fallbackTargets(excluding: sourceLanguage)
        targetLanguages = Self.sortedLanguages(
            Self.unique(visibleTargets),
            priority: [.simplifiedChinese, .traditionalChinese, .english]
        )
        statusMessage = hasSupportedTargets
            ? nil
            : "No Apple Translation targets were reported for \(sourceLanguage.displayName)."

        if targetLanguages.contains(selectedTargetLanguage) {
            return selectedTargetLanguage
        }

        for fallback in [SubtitleLanguage.simplifiedChinese, .traditionalChinese, .english] {
            if targetLanguages.contains(fallback) {
                return fallback
            }
        }

        return targetLanguages.first ?? selectedTargetLanguage
    }

    static func visibleLanguages(
        _ languages: [SubtitleLanguage],
        including selectedLanguage: SubtitleLanguage,
        priority: [SubtitleLanguage]
    ) -> [SubtitleLanguage] {
        sortedLanguages(
            unique([selectedLanguage] + languages),
            priority: priority
        )
    }

    private static func unique(_ languages: [SubtitleLanguage]) -> [SubtitleLanguage] {
        var seenIdentifiers = Set<String>()
        var uniqueLanguages: [SubtitleLanguage] = []

        for language in languages where seenIdentifiers.insert(language.identifier).inserted {
            uniqueLanguages.append(language)
        }

        return uniqueLanguages
    }

    private static func sortedLanguages(
        _ languages: [SubtitleLanguage],
        priority: [SubtitleLanguage]
    ) -> [SubtitleLanguage] {
        let uniqueLanguages = unique(languages)
        let priorityLanguages = priority.filter(uniqueLanguages.contains)
        let remainingLanguages = uniqueLanguages
            .filter { !priorityLanguages.contains($0) }
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }

        return priorityLanguages + remainingLanguages
    }

    private static func languagesAreEquivalent(
        _ lhs: SubtitleLanguage,
        _ rhs: SubtitleLanguage
    ) -> Bool {
        Locale.Language(identifier: lhs.identifier).isEquivalent(
            to: Locale.Language(identifier: rhs.identifier)
        )
    }

    private func fallbackTargets(excluding sourceLanguage: SubtitleLanguage) -> [SubtitleLanguage] {
        [SubtitleLanguage.simplifiedChinese, .traditionalChinese, .english].filter {
            !Self.languagesAreEquivalent($0, sourceLanguage)
        }
    }
}
