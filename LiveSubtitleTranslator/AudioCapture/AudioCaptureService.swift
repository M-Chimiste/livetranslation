//
//  AudioCaptureService.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import Foundation

struct AudioChunk: Equatable, Sendable {
    let id: UUID
    let captureStartHostTime: UInt64
    let captureEndHostTime: UInt64
    let sampleRate: Double
    let channelCount: Int
    let samples: [Float]

    nonisolated init(
        id: UUID = UUID(),
        captureStartHostTime: UInt64,
        captureEndHostTime: UInt64,
        sampleRate: Double,
        channelCount: Int,
        samples: [Float]
    ) {
        self.id = id
        self.captureStartHostTime = captureStartHostTime
        self.captureEndHostTime = captureEndHostTime
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.samples = samples
    }

    nonisolated var duration: TimeInterval {
        guard sampleRate > 0, channelCount > 0 else { return 0 }
        return Double(samples.count) / (sampleRate * Double(channelCount))
    }
}

struct AudioSource: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case systemOutput
        case process
    }

    let id: String
    let displayName: String
    let kind: Kind
    let processObjectID: UInt32?
    let processID: Int32?
    let bundleID: String?

    nonisolated static let systemOutput = AudioSource(
        id: "system-output",
        displayName: "System Output",
        kind: .systemOutput,
        processObjectID: nil,
        processID: nil,
        bundleID: nil
    )

    nonisolated init(
        id: String,
        displayName: String,
        kind: Kind,
        processObjectID: UInt32? = nil,
        processID: Int32? = nil,
        bundleID: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.processObjectID = processObjectID
        self.processID = processID
        self.bundleID = bundleID
    }
}

enum AudioCaptureState: Equatable, Sendable {
    case idle
    case starting
    case capturing
    case stopping
    case error(String)

    var displayName: String {
        switch self {
        case .idle:
            "Idle"
        case .starting:
            "Starting"
        case .capturing:
            "Capturing"
        case .stopping:
            "Stopping"
        case .error:
            "Error"
        }
    }

    var isRunning: Bool {
        switch self {
        case .starting, .capturing:
            true
        case .idle, .stopping, .error:
            false
        }
    }
}

protocol AudioCaptureService: AnyObject {
    var state: AudioCaptureState { get }
    var audioChunks: AsyncStream<AudioChunk> { get }
    var levelSnapshots: AsyncStream<AudioLevelSnapshot> { get }
    var preprocessingDiagnostics: AsyncStream<AudioPreprocessingDiagnostics> { get }
    var speechActivityEvents: AsyncStream<SpeechActivityEvent> { get }
    var voiceActivityDiagnostics: AsyncStream<VoiceActivityDiagnostics> { get }

    func updateVoiceActivitySettings(_ settings: VoiceActivitySettings)
    func availableSources() async throws -> [AudioSource]
    func start(source: AudioSource) async throws
    func stop() async
}
