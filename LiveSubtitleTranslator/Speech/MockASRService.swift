//
//  MockASRService.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import Foundation

struct MockASRScriptEvent: Sendable {
    let event: ASREvent
    let delay: Duration

    init(event: ASREvent, delay: Duration = .milliseconds(250)) {
        self.event = event
        self.delay = delay
    }
}

@MainActor
final class MockASRService: ASRService {
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

    private let script: [MockASRScriptEvent]
    private var eventStream = EventStream.make()
    private var shouldRenewEventStreamOnStart = false
    private var eventTask: Task<Void, Never>?

    private(set) var configuration: ASRConfiguration = .defaults
    private(set) var acceptedAudioChunks: [AudioChunk] = []
    private(set) var isRunning = false

    var events: AsyncStream<ASREvent> { eventStream.events }

    init(script: [MockASRScriptEvent]? = nil) {
        self.script = script ?? Self.defaultScript
    }

    deinit {
        eventTask?.cancel()
        eventStream.finish()
    }

    func configure(_ configuration: ASRConfiguration) async throws {
        self.configuration = configuration
    }

    func start() async throws {
        guard !isRunning else { return }
        if shouldRenewEventStreamOnStart {
            renewEventStream()
        }

        isRunning = true

        let script = script
        let continuation = eventStream.continuation
        eventTask = Task { @MainActor [weak self] in
            for scriptEvent in script {
                if Task.isCancelled { break }

                do {
                    try await Task.sleep(for: scriptEvent.delay)
                } catch {
                    break
                }

                if Task.isCancelled { break }
                continuation.yield(scriptEvent.event)
            }

            self?.isRunning = false
        }
    }

    func acceptAudioChunk(_ chunk: AudioChunk) async throws {
        acceptedAudioChunks.append(chunk)
    }

    func flush() async throws {
        guard let lastFinalSegment else { return }
        eventStream.continuation.yield(.final(lastFinalSegment))
    }

    func stop() async {
        eventTask?.cancel()
        eventTask = nil
        isRunning = false
        eventStream.finish()
        shouldRenewEventStreamOnStart = true
    }

    private var lastFinalSegment: TranscriptSegment? {
        script.compactMap { scriptEvent in
            if case let .final(segment) = scriptEvent.event {
                return segment
            }

            return nil
        }
        .last
    }

    private func renewEventStream() {
        eventStream.finish()
        eventStream = EventStream.make()
        shouldRenewEventStreamOnStart = false
    }

    static let defaultScript: [MockASRScriptEvent] = [
        MockASRScriptEvent(
            event: .partial(
                TranscriptSegment(
                    text: "Where are we",
                    startTime: 0.0,
                    endTime: 0.8,
                    stability: .partial,
                    confidence: 0.82
                )
            )
        ),
        MockASRScriptEvent(
            event: .final(
                TranscriptSegment(
                    text: "Where are we going tonight?",
                    startTime: 0.0,
                    endTime: 1.6,
                    stability: .final,
                    confidence: 0.94
                )
            )
        ),
        MockASRScriptEvent(
            event: .partial(
                TranscriptSegment(
                    text: "I don't know",
                    startTime: 1.8,
                    endTime: 2.4,
                    stability: .stablePartial,
                    confidence: 0.88
                )
            )
        ),
        MockASRScriptEvent(
            event: .final(
                TranscriptSegment(
                    text: "I don't know, but we need to leave first.",
                    startTime: 1.8,
                    endTime: 3.6,
                    stability: .final,
                    confidence: 0.93
                )
            )
        ),
        MockASRScriptEvent(
            event: .final(
                TranscriptSegment(
                    text: "This is not a good idea.",
                    startTime: 3.8,
                    endTime: 5.0,
                    stability: .final,
                    confidence: 0.91
                )
            )
        ),
        MockASRScriptEvent(
            event: .final(
                TranscriptSegment(
                    text: "Wait, I hear someone coming.",
                    startTime: 5.2,
                    endTime: 6.8,
                    stability: .final,
                    confidence: 0.95
                )
            )
        )
    ]
}
