//
//  AppleTranslationService.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/21/26.
//

import Foundation
import Translation

enum AppleTranslationAvailabilityStatus: Equatable, Sendable {
    case installed
    case supported
    case unsupported
}

enum AppleTranslationStrategy: Equatable, Sendable {
    case lowLatency
    case highFidelity

    init(latencyProfile: LatencyProfile) {
        switch latencyProfile {
        case .fast, .balanced:
            self = .lowLatency
        case .moreAccurate:
            self = .highFidelity
        }
    }
}

struct AppleTranslationClientConfiguration: Equatable, Sendable {
    let sourceLanguageIdentifier: String
    let targetLanguageIdentifier: String
    let strategy: AppleTranslationStrategy
}

@MainActor
protocol AppleTranslationClient: AnyObject {
    func supportedLanguageIdentifiers() async -> [String]

    func availabilityStatus(
        from sourceLanguageIdentifier: String,
        to targetLanguageIdentifier: String
    ) async -> AppleTranslationAvailabilityStatus

    func translate(
        _ text: String,
        configuration: AppleTranslationClientConfiguration,
        shouldPrepare: Bool
    ) async throws -> String
}

enum TranslationServiceError: LocalizedError, Equatable {
    case nothingToTranslate
    case unsupportedAppleLanguagePair(source: String, target: String)
    case remoteLANUnavailable

    var errorDescription: String? {
        switch self {
        case .nothingToTranslate:
            "There is no text to translate."
        case let .unsupportedAppleLanguagePair(source, target):
            "Apple Translation does not support \(source) to \(target) on this Mac."
        case .remoteLANUnavailable:
            "Remote LAN translation is not implemented yet."
        }
    }
}

@MainActor
final class AppleTranslationService: TranslationService {
    private let client: AppleTranslationClient
    private let latencyProfileProvider: @MainActor () -> LatencyProfile

    init(
        client: AppleTranslationClient? = nil,
        latencyProfileProvider: @escaping @MainActor () -> LatencyProfile = { .balanced }
    ) {
        self.client = client ?? LiveAppleTranslationClient()
        self.latencyProfileProvider = latencyProfileProvider
    }

    func translate(
        segment: TranscriptSegment,
        context: [TranscriptSegment],
        targetLanguage: SubtitleLanguage
    ) async throws -> TranslationSegment {
        let sourceText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            throw TranslationServiceError.nothingToTranslate
        }

        let sourceLanguageIdentifier = Self.sourceLanguageIdentifier(for: segment)
        let targetLanguageIdentifier = Self.targetLanguageIdentifier(for: targetLanguage)
        let status = await client.availabilityStatus(
            from: sourceLanguageIdentifier,
            to: targetLanguageIdentifier
        )

        guard status != .unsupported else {
            throw TranslationServiceError.unsupportedAppleLanguagePair(
                source: sourceLanguageIdentifier,
                target: targetLanguageIdentifier
            )
        }

        let configuration = AppleTranslationClientConfiguration(
            sourceLanguageIdentifier: sourceLanguageIdentifier,
            targetLanguageIdentifier: targetLanguageIdentifier,
            strategy: AppleTranslationStrategy(latencyProfile: latencyProfileProvider())
        )
        let translatedText = try await client.translate(
            sourceText,
            configuration: configuration,
            shouldPrepare: status == .supported
        )

        return TranslationSegment(
            transcriptID: segment.id,
            sourceText: sourceText,
            translatedText: translatedText.trimmingCharacters(in: .whitespacesAndNewlines),
            targetLanguage: targetLanguage
        )
    }

    nonisolated static func sourceLanguageIdentifier(for segment: TranscriptSegment) -> String {
        SubtitleLanguage(segment.sourceLanguage).identifier
    }

    nonisolated static func targetLanguageIdentifier(for targetLanguage: SubtitleLanguage) -> String {
        targetLanguage.identifier
    }
}

@MainActor
final class LiveAppleTranslationClient: AppleTranslationClient {
    private let availability = LanguageAvailability()
    private var cachedConfiguration: AppleTranslationClientConfiguration?
    private var cachedSession: TranslationSession?

    func supportedLanguageIdentifiers() async -> [String] {
        await availability.supportedLanguages.map(\.minimalIdentifier)
    }

    func availabilityStatus(
        from sourceLanguageIdentifier: String,
        to targetLanguageIdentifier: String
    ) async -> AppleTranslationAvailabilityStatus {
        let status = await availability.status(
            from: Locale.Language(identifier: sourceLanguageIdentifier),
            to: Locale.Language(identifier: targetLanguageIdentifier)
        )

        switch status {
        case .installed:
            return .installed
        case .supported:
            return .supported
        case .unsupported:
            return .unsupported
        @unknown default:
            return .unsupported
        }
    }

    func translate(
        _ text: String,
        configuration: AppleTranslationClientConfiguration,
        shouldPrepare: Bool
    ) async throws -> String {
        let session = session(for: configuration)

        if shouldPrepare {
            try await session.prepareTranslation()
        }

        let response = try await session.translate(text)
        return response.targetText
    }

    private func session(for configuration: AppleTranslationClientConfiguration) -> TranslationSession {
        if let cachedSession, cachedConfiguration == configuration {
            return cachedSession
        }

        let sourceLanguage = Locale.Language(identifier: configuration.sourceLanguageIdentifier)
        let targetLanguage = Locale.Language(identifier: configuration.targetLanguageIdentifier)
        let session = TranslationSession(
            installedSource: sourceLanguage,
            target: targetLanguage,
            preferredStrategy: configuration.strategy.translationStrategy
        )

        cachedConfiguration = configuration
        cachedSession = session

        return session
    }
}

private extension AppleTranslationStrategy {
    var translationStrategy: TranslationSession.Strategy {
        switch self {
        case .lowLatency:
            .lowLatency
        case .highFidelity:
            .highFidelity
        }
    }
}
