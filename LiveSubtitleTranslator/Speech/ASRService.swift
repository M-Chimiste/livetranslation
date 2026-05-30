//
//  ASRService.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import Foundation

struct TranscriptSegment: Identifiable, Equatable, Sendable {
    enum Stability: Equatable, Sendable {
        case partial
        case stablePartial
        case final
    }

    let id: UUID
    let sourceLanguage: String
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let createdAt: Date
    let stability: Stability
    let confidence: Double?

    init(
        id: UUID = UUID(),
        sourceLanguage: String = "en",
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        createdAt: Date = Date(),
        stability: Stability,
        confidence: Double? = nil
    ) {
        self.id = id
        self.sourceLanguage = sourceLanguage
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.createdAt = createdAt
        self.stability = stability
        self.confidence = confidence
    }
}

struct ASRConfiguration: Equatable, Sendable {
    var sourceLanguage: String
    var latencyProfile: LatencyProfile
    var modelID: String?

    static let defaults = ASRConfiguration(
        sourceLanguage: "en",
        latencyProfile: .balanced,
        modelID: LocalASRSettings.defaults.modelID
    )

    init(
        sourceLanguage: String,
        latencyProfile: LatencyProfile,
        modelID: String? = LocalASRSettings.defaults.modelID
    ) {
        self.sourceLanguage = SubtitleLanguage(sourceLanguage).identifier
        self.latencyProfile = latencyProfile
        self.modelID = modelID.map(LocalASRSettings.canonicalModelID(for:))
    }
}

enum ASREvent: Equatable, Sendable {
    case partial(TranscriptSegment)
    case final(TranscriptSegment)
    case error(String)
}

protocol ASRService: AnyObject {
    var events: AsyncStream<ASREvent> { get }

    func configure(_ configuration: ASRConfiguration) async throws
    func start() async throws
    func acceptAudioChunk(_ chunk: AudioChunk) async throws
    func flush() async throws
    func stop() async
}
