//
//  ParakeetASRService.swift
//  LiveSubtitleTranslator
//
//  Replaces the former WhisperKit ASR path with NVIDIA Parakeet TDT 0.6b
//  running on the Apple Neural Engine via the FluidAudio CoreML package.
//
//  Parakeet v3 is a batch transcriber (no streaming partials), which maps onto
//  the existing batch/flush ASRService contract: samples accumulate via
//  `acceptAudioChunk` and a single `.final` segment is emitted on `flush()`
//  (driven by VAD `speechEnded` and the live auto-flush timer).
//

import Foundation
import FluidAudio

nonisolated struct ParakeetTranscriptionOutput: Equatable, Sendable {
    let text: String

    nonisolated init(text: String) {
        self.text = text
    }
}

nonisolated protocol ParakeetTranscribing: AnyObject {
    func load(modelID: String) async throws
    func transcribe(samples: [Float]) async throws -> ParakeetTranscriptionOutput
}

enum ParakeetASRError: LocalizedError, Equatable {
    case notRunning
    case emptyModelID

    var errorDescription: String? {
        switch self {
        case .notRunning:
            "Parakeet ASR is not running."
        case .emptyModelID:
            "Parakeet model ID is empty."
        }
    }
}

actor LiveParakeetTranscriber: ParakeetTranscribing {
    /// Parakeet's preprocessor expects at least a short window of audio; pad very
    /// short flushes up to 1 s so brief utterances don't fail the mel front end.
    private static let minimumSampleCount = 16_000

    private var loadedModelID: String?
    private var manager: AsrManager?

    func load(modelID: String) async throws {
        let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelID.isEmpty else {
            throw ParakeetASRError.emptyModelID
        }

        if loadedModelID == trimmedModelID, manager != nil {
            return
        }

        let version: AsrModelVersion = trimmedModelID == LocalASRSettings.parakeetV2ModelID ? .v2 : .v3
        let models = try await AsrModels.downloadAndLoad(version: version)
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)

        self.manager = manager
        loadedModelID = trimmedModelID
    }

    func transcribe(samples: [Float]) async throws -> ParakeetTranscriptionOutput {
        guard let manager else {
            throw ParakeetASRError.notRunning
        }

        let padded: [Float]
        if samples.count < Self.minimumSampleCount {
            padded = samples + [Float](repeating: 0, count: Self.minimumSampleCount - samples.count)
        } else {
            padded = samples
        }

        let result = try await manager.transcribe(padded, source: .system)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParakeetTranscriptionOutput(text: text)
    }
}

@MainActor
final class ParakeetASRService: ASRService {
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

    private let transcriber: ParakeetTranscribing
    private var eventStream = EventStream.make()
    private var shouldRenewEventStreamOnStart = false
    private var pendingSamples: [Float] = []
    private var pendingDuration: TimeInterval = 0

    private(set) var configuration: ASRConfiguration = .defaults
    private(set) var isRunning = false

    var events: AsyncStream<ASREvent> { eventStream.events }

    init(transcriber: ParakeetTranscribing = LiveParakeetTranscriber()) {
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

        let modelID = LocalASRSettings.canonicalModelID(
            for: configuration.modelID ?? LocalASRSettings.defaults.modelID
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
            let output = try await transcriber.transcribe(samples: samples)
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
