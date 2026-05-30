//
//  VoiceActivity.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/21/26.
//

import Foundation

enum VADSensitivity: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case high
    case balanced
    case low

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .high:
            "High"
        case .balanced:
            "Balanced"
        case .low:
            "Low"
        }
    }

    nonisolated var thresholds: VoiceActivityThresholds {
        switch self {
        case .high:
            VoiceActivityThresholds(startRMS: 0.008, continueRMS: 0.004)
        case .balanced:
            VoiceActivityThresholds(startRMS: 0.015, continueRMS: 0.008)
        case .low:
            VoiceActivityThresholds(startRMS: 0.030, continueRMS: 0.015)
        }
    }
}

struct VoiceActivitySettings: Codable, Equatable, Sendable {
    var sensitivity: VADSensitivity
    var finalSilenceDuration: TimeInterval

    nonisolated static let defaults = VoiceActivitySettings(
        sensitivity: .balanced,
        finalSilenceDuration: 1.0
    )

    nonisolated init(
        sensitivity: VADSensitivity,
        finalSilenceDuration: TimeInterval
    ) {
        self.sensitivity = sensitivity
        self.finalSilenceDuration = finalSilenceDuration
    }

    nonisolated var effectiveFinalSilenceDuration: TimeInterval {
        max(0, finalSilenceDuration)
    }

    nonisolated var finalSilenceDurationDisplayValue: String {
        String(format: "%.1f s", finalSilenceDuration)
    }
}

struct VoiceActivityThresholds: Equatable, Sendable {
    let startRMS: Float
    let continueRMS: Float

    nonisolated init(startRMS: Float, continueRMS: Float) {
        self.startRMS = startRMS
        self.continueRMS = continueRMS
    }
}

enum VoiceActivityState: String, Equatable, Sendable {
    case inactive
    case active

    nonisolated var displayName: String {
        switch self {
        case .inactive:
            "Inactive"
        case .active:
            "Active"
        }
    }
}

struct SpeechSegmentMetadata: Equatable, Sendable {
    let id: UUID
    let captureStartHostTime: UInt64
    let captureEndHostTime: UInt64
    let chunkCount: Int
    let duration: TimeInterval
    let peak: Float
    let rms: Float

    nonisolated init(
        id: UUID,
        captureStartHostTime: UInt64,
        captureEndHostTime: UInt64,
        chunkCount: Int,
        duration: TimeInterval,
        peak: Float,
        rms: Float
    ) {
        self.id = id
        self.captureStartHostTime = captureStartHostTime
        self.captureEndHostTime = captureEndHostTime
        self.chunkCount = chunkCount
        self.duration = duration
        self.peak = peak
        self.rms = rms
    }
}

enum SpeechActivityEvent: Equatable, Sendable {
    case speechStarted(SpeechSegmentMetadata)
    case speechChunk(AudioChunk)
    case speechEnded(SpeechSegmentMetadata)
}

struct VoiceActivityDiagnostics: Equatable, Sendable {
    var activityState: VoiceActivityState
    var completedSegmentCount: Int
    var emittedSpeechChunkCount: Int
    var lastSpeechDuration: TimeInterval?
    var currentSilenceDuration: TimeInterval
    var lastChunkRMS: Float
    var lastChunkPeak: Float

    nonisolated static let zero = VoiceActivityDiagnostics(
        activityState: .inactive,
        completedSegmentCount: 0,
        emittedSpeechChunkCount: 0,
        lastSpeechDuration: nil,
        currentSilenceDuration: 0,
        lastChunkRMS: 0,
        lastChunkPeak: 0
    )

    nonisolated init(
        activityState: VoiceActivityState,
        completedSegmentCount: Int,
        emittedSpeechChunkCount: Int,
        lastSpeechDuration: TimeInterval?,
        currentSilenceDuration: TimeInterval,
        lastChunkRMS: Float,
        lastChunkPeak: Float
    ) {
        self.activityState = activityState
        self.completedSegmentCount = completedSegmentCount
        self.emittedSpeechChunkCount = emittedSpeechChunkCount
        self.lastSpeechDuration = lastSpeechDuration
        self.currentSilenceDuration = currentSilenceDuration
        self.lastChunkRMS = lastChunkRMS
        self.lastChunkPeak = lastChunkPeak
    }

    nonisolated var activityStateDisplayValue: String {
        activityState.displayName
    }

    nonisolated var completedSegmentCountDisplayValue: String {
        "\(completedSegmentCount)"
    }

    nonisolated var emittedSpeechChunkCountDisplayValue: String {
        "\(emittedSpeechChunkCount)"
    }

    nonisolated var lastSpeechDurationDisplayValue: String {
        guard let lastSpeechDuration else { return "None" }
        return String(format: "%.2f s", lastSpeechDuration)
    }

    nonisolated var currentSilenceDurationDisplayValue: String {
        String(format: "%.2f s", currentSilenceDuration)
    }

    nonisolated var lastChunkRMSDisplayValue: String {
        Self.normalizedDisplayValue(for: lastChunkRMS)
    }

    nonisolated var lastChunkPeakDisplayValue: String {
        Self.normalizedDisplayValue(for: lastChunkPeak)
    }

    private nonisolated static func normalizedDisplayValue(for value: Float) -> String {
        let normalizedValue = String(format: "%.3f", min(max(value, 0), 1))
        let decibels = value > 0 ? 20 * log10(Double(value)) : -.infinity
        let decibelValue = decibels.isFinite ? String(format: "%.1f dBFS", decibels) : "-∞ dBFS"
        return "\(normalizedValue) (\(decibelValue))"
    }
}

struct EnergyVoiceActivityDetector: Sendable {
    let settings: VoiceActivitySettings

    private var diagnostics: VoiceActivityDiagnostics
    private var activeSegmentID: UUID?
    private var activeStartHostTime: UInt64 = 0
    private var activeEndHostTime: UInt64 = 0
    private var activeChunkCount = 0
    private var activeSampleCount = 0
    private var activeSumOfSquares: Float = 0
    private var activePeak: Float = 0
    private var activeDuration: TimeInterval = 0

    nonisolated init(settings: VoiceActivitySettings = .defaults) {
        self.settings = settings
        self.diagnostics = .zero
    }

    nonisolated var currentDiagnostics: VoiceActivityDiagnostics {
        diagnostics
    }

    nonisolated mutating func process(_ chunk: AudioChunk) -> [SpeechActivityEvent] {
        let level = AudioLevelCalculator.snapshot(
            samples: chunk.samples,
            sampleRate: chunk.sampleRate,
            channelCount: chunk.channelCount
        )
        diagnostics.lastChunkRMS = level.rms
        diagnostics.lastChunkPeak = level.peak

        if activeSegmentID == nil {
            return processInactiveChunk(chunk, level: level)
        }

        return processActiveChunk(chunk, level: level)
    }

    nonisolated mutating func reset() {
        diagnostics = .zero
        activeSegmentID = nil
        activeStartHostTime = 0
        activeEndHostTime = 0
        activeChunkCount = 0
        activeSampleCount = 0
        activeSumOfSquares = 0
        activePeak = 0
        activeDuration = 0
    }

    private nonisolated mutating func processInactiveChunk(
        _ chunk: AudioChunk,
        level: AudioLevelSnapshot
    ) -> [SpeechActivityEvent] {
        if level.rms >= settings.sensitivity.thresholds.startRMS {
            startSegment(with: chunk)
            appendSpeechChunk(chunk, level: level)
            return [
                .speechStarted(currentMetadata()),
                .speechChunk(chunk)
            ]
        }

        diagnostics.currentSilenceDuration += chunk.duration
        diagnostics.activityState = .inactive
        return []
    }

    private nonisolated mutating func processActiveChunk(
        _ chunk: AudioChunk,
        level: AudioLevelSnapshot
    ) -> [SpeechActivityEvent] {
        if level.rms >= settings.sensitivity.thresholds.continueRMS {
            diagnostics.currentSilenceDuration = 0
            appendSpeechChunk(chunk, level: level)
            return [.speechChunk(chunk)]
        }

        diagnostics.currentSilenceDuration += chunk.duration
        guard diagnostics.currentSilenceDuration >= settings.effectiveFinalSilenceDuration else {
            return []
        }

        let metadata = currentMetadata()
        diagnostics.activityState = .inactive
        diagnostics.completedSegmentCount += 1
        diagnostics.lastSpeechDuration = metadata.duration
        clearActiveSegment()

        return [.speechEnded(metadata)]
    }

    private nonisolated mutating func startSegment(with chunk: AudioChunk) {
        activeSegmentID = UUID()
        activeStartHostTime = chunk.captureStartHostTime
        activeEndHostTime = chunk.captureStartHostTime
        activeChunkCount = 0
        activeSampleCount = 0
        activeSumOfSquares = 0
        activePeak = 0
        activeDuration = 0
        diagnostics.activityState = .active
        diagnostics.currentSilenceDuration = 0
    }

    private nonisolated mutating func appendSpeechChunk(
        _ chunk: AudioChunk,
        level: AudioLevelSnapshot
    ) {
        activeEndHostTime = chunk.captureEndHostTime
        activeChunkCount += 1
        activeDuration += chunk.duration
        activeSampleCount += chunk.samples.count
        activeSumOfSquares += level.rms * level.rms * Float(chunk.samples.count)
        activePeak = max(activePeak, level.peak)
        diagnostics.activityState = .active
        diagnostics.emittedSpeechChunkCount += 1
    }

    private nonisolated func currentMetadata() -> SpeechSegmentMetadata {
        let rms = activeSampleCount > 0
            ? sqrt(activeSumOfSquares / Float(activeSampleCount))
            : 0

        return SpeechSegmentMetadata(
            id: activeSegmentID ?? UUID(),
            captureStartHostTime: activeStartHostTime,
            captureEndHostTime: activeEndHostTime,
            chunkCount: activeChunkCount,
            duration: activeDuration,
            peak: activePeak,
            rms: rms
        )
    }

    private nonisolated mutating func clearActiveSegment() {
        activeSegmentID = nil
        activeStartHostTime = 0
        activeEndHostTime = 0
        activeChunkCount = 0
        activeSampleCount = 0
        activeSumOfSquares = 0
        activePeak = 0
        activeDuration = 0
    }
}
