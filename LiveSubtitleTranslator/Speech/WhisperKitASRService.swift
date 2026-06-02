//
//  WhisperKitASRService.swift
//  LiveSubtitleTranslator
//
//  Selectable alternative ASR backend (alongside Parakeet). Uses WhisperKit
//  CoreML models via the argmax-oss-swift package. Same batch/flush ASRService
//  contract as the Parakeet service: samples accumulate via `acceptAudioChunk`
//  and a single `.final` segment is emitted on `flush()`.
//

import Foundation
import WhisperKit

nonisolated struct WhisperKitTranscriptionOutput: Equatable, Sendable {
    let text: String

    nonisolated init(text: String) {
        self.text = text
    }
}

nonisolated protocol WhisperKitTranscribing: AnyObject {
    func load(modelID: String) async throws
    func transcribe(samples: [Float], language: String) async throws -> WhisperKitTranscriptionOutput
}

enum WhisperKitASRError: LocalizedError, Equatable {
    case notRunning
    case emptyModelID

    var errorDescription: String? {
        switch self {
        case .notRunning:
            "WhisperKit ASR is not running."
        case .emptyModelID:
            "WhisperKit model ID is empty."
        }
    }
}

actor LiveWhisperKitTranscriber: WhisperKitTranscribing {
    private var loadedModelID: String?
    private var whisperKit: WhisperKit?

    func load(modelID: String) async throws {
        let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelID.isEmpty else {
            throw WhisperKitASRError.emptyModelID
        }

        if loadedModelID == trimmedModelID, whisperKit != nil {
            return
        }

        let config = WhisperKitConfig(model: trimmedModelID)
        whisperKit = try await WhisperKit(config)
        loadedModelID = trimmedModelID
    }

    func transcribe(samples: [Float], language: String) async throws -> WhisperKitTranscriptionOutput {
        guard let whisperKit else {
            throw WhisperKitASRError.notRunning
        }

        var decodingOptions = DecodingOptions()
        decodingOptions.language = language

        let results = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: decodingOptions
        )
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return WhisperKitTranscriptionOutput(text: text)
    }
}

@MainActor
final class WhisperKitASRService: ASRService {
    private nonisolated struct EventStream {
        let events: AsyncStream<ASREvent>
        let continuation: AsyncStream<ASREvent>.Continuation

        static func make() -> EventStream {
            let stream = AsyncStream<ASREvent>.makeStream()
            return EventStream(events: stream.stream, continuation: stream.continuation)
        }

        func finish() {
            continuation.finish()
        }
    }

    private let transcriber: WhisperKitTranscribing
    private var eventStream = EventStream.make()
    private var shouldRenewEventStreamOnStart = false
    private var pendingSamples: [Float] = []
    private var pendingDuration: TimeInterval = 0

    private(set) var configuration: ASRConfiguration = .defaults
    private(set) var isRunning = false

    var events: AsyncStream<ASREvent> { eventStream.events }

    init(transcriber: WhisperKitTranscribing = LiveWhisperKitTranscriber()) {
        self.transcriber = transcriber
    }

    deinit {
        eventStream.finish()
    }

    var pendingSampleCount: Int {
        pendingSamples.count
    }

    func configure(_ configuration: ASRConfiguration) async throws {
        self.configuration = configuration
    }

    func start() async throws {
        guard !isRunning else { return }
        if shouldRenewEventStreamOnStart {
            renewEventStream()
        }

        let modelID = LocalASRSettings.canonicalWhisperKitModelID(
            for: configuration.modelID ?? LocalASRSettings.whisperLargeV3ModelID
        )

        do {
            try await transcriber.load(modelID: modelID)
            isRunning = true
        } catch {
            eventStream.continuation.yield(.error(error.localizedDescription))
            throw error
        }
    }

    func acceptAudioChunk(_ chunk: AudioChunk) async throws {
        guard isRunning else { return }

        pendingSamples.append(contentsOf: chunk.samples)
        pendingDuration += chunk.duration
    }

    func flush() async throws {
        guard isRunning, !pendingSamples.isEmpty else { return }

        let samples = pendingSamples
        let duration = pendingDuration
        clearPendingAudio()

        do {
            let output = try await transcriber.transcribe(
                samples: samples,
                language: SubtitleLanguage(configuration.sourceLanguage).whisperLanguageCode
            )
            let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }

            eventStream.continuation.yield(
                .final(
                    TranscriptSegment(
                        sourceLanguage: configuration.sourceLanguage,
                        text: text,
                        startTime: 0,
                        endTime: duration,
                        stability: .final
                    )
                )
            )
        } catch {
            eventStream.continuation.yield(.error(error.localizedDescription))
            throw error
        }
    }

    func stop() async {
        clearPendingAudio()
        isRunning = false
        eventStream.finish()
        shouldRenewEventStreamOnStart = true
    }

    private func clearPendingAudio() {
        pendingSamples.removeAll(keepingCapacity: true)
        pendingDuration = 0
    }

    private func renewEventStream() {
        eventStream.finish()
        eventStream = EventStream.make()
        shouldRenewEventStreamOnStart = false
    }
}
