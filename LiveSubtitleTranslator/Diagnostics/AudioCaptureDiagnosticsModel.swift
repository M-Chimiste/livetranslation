//
//  AudioCaptureDiagnosticsModel.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import Combine
import Foundation

enum AudioCapturePermissionStatus: String, Equatable, Sendable {
    case notRequested
    case authorized
    case denied
    case unknown

    var displayName: String {
        switch self {
        case .notRequested:
            "Not Requested"
        case .authorized:
            "Authorized"
        case .denied:
            "Denied"
        case .unknown:
            "Unknown"
        }
    }
}

enum AudioSourceAvailabilityStatus: String, Equatable, Sendable {
    case placeholderOnly
    case available
    case unavailable

    var displayName: String {
        switch self {
        case .placeholderOnly:
            "Placeholder Only"
        case .available:
            "Available"
        case .unavailable:
            "Unavailable"
        }
    }
}

struct AudioCaptureDiagnosticsState: Equatable, Sendable {
    var permissionStatus: AudioCapturePermissionStatus
    var captureState: AudioCaptureState
    var sourceAvailability: AudioSourceAvailabilityStatus
    var availableSources: [AudioSource]
    var lastLevel: AudioLevelSnapshot
    var preprocessingDiagnostics: AudioPreprocessingDiagnostics
    var voiceActivityDiagnostics: VoiceActivityDiagnostics
    var asrDiagnostics: ASRDiagnosticsState
    var captureWarningMessage: String?
    var lastErrorMessage: String?

    nonisolated static let placeholder = AudioCaptureDiagnosticsState(
        permissionStatus: .notRequested,
        captureState: .idle,
        sourceAvailability: .placeholderOnly,
        availableSources: [.systemOutput],
        lastLevel: .zero,
        preprocessingDiagnostics: .zero,
        voiceActivityDiagnostics: .zero,
        asrDiagnostics: .placeholder,
        captureWarningMessage: nil,
        lastErrorMessage: nil
    )

    nonisolated init(
        permissionStatus: AudioCapturePermissionStatus,
        captureState: AudioCaptureState,
        sourceAvailability: AudioSourceAvailabilityStatus,
        availableSources: [AudioSource] = [.systemOutput],
        lastLevel: AudioLevelSnapshot = .zero,
        preprocessingDiagnostics: AudioPreprocessingDiagnostics = .zero,
        voiceActivityDiagnostics: VoiceActivityDiagnostics = .zero,
        asrDiagnostics: ASRDiagnosticsState = .placeholder,
        captureWarningMessage: String? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.permissionStatus = permissionStatus
        self.captureState = captureState
        self.sourceAvailability = sourceAvailability
        self.availableSources = availableSources
        self.lastLevel = lastLevel
        self.preprocessingDiagnostics = preprocessingDiagnostics
        self.voiceActivityDiagnostics = voiceActivityDiagnostics
        self.asrDiagnostics = asrDiagnostics
        self.captureWarningMessage = captureWarningMessage
        self.lastErrorMessage = lastErrorMessage
    }

    var sourceCountDisplayValue: String {
        "\(availableSources.count)"
    }
}

@MainActor
final class AudioCaptureDiagnosticsModel: ObservableObject {
    private static let liveASRAutoFlushDuration: TimeInterval = 3.0
    private static let silentCaptureWarningDuration: TimeInterval = 5.0
    private static let systemAudioPermissionPath = "System Settings > Privacy & Security > Screen & System Audio Recording > System Audio Recording Only"
    private static let silentCaptureWarningMessage = "No captured audio detected yet. Confirm Live Subtitle Translator is allowed in \(systemAudioPermissionPath) and that the video is playing through the current Mac output device."

    @Published private(set) var state: AudioCaptureDiagnosticsState

    var asrEventSink: (@MainActor (ASREvent) async -> Void)?
    var audioActivitySink: (@MainActor () async -> Void)?

    private static let deniedPermissionMessage = "System audio recording permission is denied. Enable Live Subtitle Translator in System Settings > Privacy & Security > Screen & System Audio Recording > System Audio Recording Only, then quit and relaunch the app. If the app is missing there, reset the permission row with tccutil and start capture again."
    private static let unavailablePermissionMessage = "System audio recording permission could not be requested. Open System Settings > Privacy & Security > Screen & System Audio Recording > System Audio Recording Only and enable Live Subtitle Translator if it appears there."

    private let captureService: AudioCaptureService
    private let parakeetASRService: ASRService
    private let whisperKitASRService: ASRService
    /// The ASR service for the backend selected when capture last started.
    private var activeASRService: ASRService
    private let permissionProvider: AudioCapturePermissionProviding
    private var levelTask: Task<Void, Never>?
    private var audioChunkTask: Task<Void, Never>?
    private var preprocessingDiagnosticsTask: Task<Void, Never>?
    private var speechActivityTask: Task<Void, Never>?
    private var voiceActivityDiagnosticsTask: Task<Void, Never>?
    /// Upper bound on final segments coalesced into one sink event (~3 s of
    /// speech each). Beyond this the oldest are dropped: an overloaded pipeline
    /// must stay bounded, and the overlay can't display that much text anyway.
    private static let maxPendingSinkSegments = 4

    private var asrEventTask: Task<Void, Never>?
    /// Final segments that arrived while the sink (e.g. translation) was busy.
    /// They are coalesced into a single merged segment when the sink frees up,
    /// so a slow translation skips no content yet never builds a queue — one
    /// translation call catches the subtitle up to the speaker.
    private var pendingFinalSinkSegments: [TranscriptSegment] = []
    /// Newest non-final event (partial/error) awaiting the sink; latest wins.
    private var pendingOtherSinkEvent: ASREvent?
    private var isForwardingEventToSink = false
    private var isFlushingASR = false
    private var serviceEmittedChunkCount: Int?
    private var serviceVoiceActivityDiagnosticsSeen = false
    private var shouldRouteAudioToASR = false
    private var captureObservationGeneration = 0
    private var asrObservationGeneration = 0
    private var asrRoutingGeneration = 0
    private var pendingASRDuration: TimeInterval = 0
    private var silentCaptureDuration: TimeInterval = 0
    private var hasReportedAudioActivity = false
    private var lastASRBackend: ASRBackend = .mock
    private var lastASRModelID = LocalASRSettings.defaults.modelID

    convenience init(state: AudioCaptureDiagnosticsState = .placeholder) {
        self.init(
            captureService: ProcessTapAudioCaptureService(),
            asrService: ParakeetASRService(),
            whisperKitASRService: WhisperKitASRService(),
            permissionProvider: SystemAudioCapturePermissionProvider(),
            state: state
        )
    }

    init(
        captureService: AudioCaptureService,
        asrService: ASRService? = nil,
        whisperKitASRService: ASRService? = nil,
        permissionProvider: AudioCapturePermissionProviding? = nil,
        state: AudioCaptureDiagnosticsState = .placeholder
    ) {
        self.captureService = captureService
        let parakeet = asrService ?? ParakeetASRService()
        self.parakeetASRService = parakeet
        self.whisperKitASRService = whisperKitASRService ?? WhisperKitASRService()
        self.activeASRService = parakeet
        let resolvedPermissionProvider = permissionProvider ?? StaticAudioCapturePermissionProvider(status: .authorized)
        self.permissionProvider = resolvedPermissionProvider
        self.state = state
        self.state.permissionStatus = resolvedPermissionProvider.currentStatus()
    }

    deinit {
        levelTask?.cancel()
        audioChunkTask?.cancel()
        preprocessingDiagnosticsTask?.cancel()
        speechActivityTask?.cancel()
        voiceActivityDiagnosticsTask?.cancel()
        asrEventTask?.cancel()
    }

    func refreshSources() async {
        do {
            let sources = try await captureService.availableSources()
            state.availableSources = sources
            state.sourceAvailability = sources.isEmpty ? .unavailable : .available
            state.lastErrorMessage = nil
        } catch {
            state.sourceAvailability = .unavailable
            state.lastErrorMessage = error.localizedDescription
        }
    }

    func reportSessionError(_ message: String) {
        state.captureState = .error(message)
        state.lastErrorMessage = message
    }

    func startCapture(
        audioSourceOption: AudioSourceOption,
        voiceActivitySettings: VoiceActivitySettings = .defaults,
        asrBackend: ASRBackend = .mock,
        localASRSettings: LocalASRSettings = .defaults,
        sourceLanguage: SubtitleLanguage = .english,
        latencyProfile: LatencyProfile = .balanced,
        requiresASR: Bool = false
    ) async {
        guard audioSourceOption == .systemOutput else {
            let error = AudioCaptureError.selectedAppCaptureUnavailable
            state.captureState = .error(error.localizedDescription)
            state.lastErrorMessage = error.localizedDescription
            return
        }

        guard await requestAudioCapturePermissionIfNeeded() else {
            return
        }

        captureService.updateVoiceActivitySettings(voiceActivitySettings)
        let captureWasAlreadyRunning = captureService.state.isRunning || state.captureState.isRunning
        if captureWasAlreadyRunning {
            state.captureState = captureService.state
        } else {
            state.captureState = .starting
            state.lastLevel = .zero
            state.preprocessingDiagnostics = .zero
            state.voiceActivityDiagnostics = .zero
            serviceEmittedChunkCount = nil
            serviceVoiceActivityDiagnosticsSeen = false
            silentCaptureDuration = 0
            state.captureWarningMessage = nil
        }

        lastASRBackend = asrBackend
        lastASRModelID = localASRSettings.activeModelID(for: asrBackend)
        state.asrDiagnostics = .idle(
            backend: asrBackend,
            modelID: localASRSettings.modelID
        )
        shouldRouteAudioToASR = false
        asrRoutingGeneration += 1
        pendingASRDuration = 0
        hasReportedAudioActivity = false
        state.lastErrorMessage = nil
        if captureWasAlreadyRunning {
            ensureCaptureObservationTasks()
        }

        let didStartASR = await startASRIfNeeded(
            backend: asrBackend,
            localASRSettings: localASRSettings,
            sourceLanguage: sourceLanguage,
            latencyProfile: latencyProfile
        )
        guard didStartASR || !requiresASR else {
            let message = state.asrDiagnostics.lastErrorMessage ?? "Local Parakeet ASR failed to start."
            state.captureState = captureWasAlreadyRunning ? captureService.state : .error(message)
            state.lastErrorMessage = message
            if !captureWasAlreadyRunning {
                cancelCaptureObservationTasks()
            }
            return
        }

        guard !captureWasAlreadyRunning else {
            state.captureState = captureService.state
            state.permissionStatus = permissionProvider.currentStatus()
            state.sourceAvailability = .available
            return
        }

        do {
            try await captureService.start(source: .systemOutput)
            startCaptureObservationTasks()
            state.captureState = captureService.state
            state.permissionStatus = permissionProvider.currentStatus()
            state.sourceAvailability = .available
        } catch {
            await activeASRService.stop()
            state.captureState = .error(error.localizedDescription)
            state.lastErrorMessage = error.localizedDescription
            shouldRouteAudioToASR = false
            await cancelCaptureObservationTasksAndWait()
        }
    }

    func stopASRRouting() async {
        shouldRouteAudioToASR = false
        asrRoutingGeneration += 1
        pendingASRDuration = 0
        asrEventSink = nil
        audioActivitySink = nil
        await cancelASREventTaskAndWait()
        await activeASRService.stop()
        state.asrDiagnostics = .idle(
            backend: lastASRBackend,
            modelID: lastASRModelID
        )
    }

    func stopCapture() async {
        state.captureState = .stopping
        shouldRouteAudioToASR = false
        asrRoutingGeneration += 1
        pendingASRDuration = 0
        await cancelCaptureObservationTasksAndWait()

        await captureService.stop()
        await activeASRService.stop()
        state.captureState = captureService.state
        state.lastLevel = .zero
        state.preprocessingDiagnostics = .zero
        state.voiceActivityDiagnostics = .zero
        state.asrDiagnostics = .idle(
            backend: lastASRBackend,
            modelID: lastASRModelID
        )
        serviceEmittedChunkCount = nil
        serviceVoiceActivityDiagnosticsSeen = false
        silentCaptureDuration = 0
        hasReportedAudioActivity = false
        asrEventSink = nil
        audioActivitySink = nil
        state.captureWarningMessage = nil
    }

    private func requestAudioCapturePermissionIfNeeded() async -> Bool {
        let currentStatus = permissionProvider.currentStatus()
        state.permissionStatus = currentStatus

        switch currentStatus {
        case .authorized:
            return true
        case .denied:
            state.captureState = .error(Self.deniedPermissionMessage)
            state.lastErrorMessage = Self.deniedPermissionMessage
            return false
        case .notRequested, .unknown:
            let requestedStatus = await permissionProvider.requestPermission()
            state.permissionStatus = requestedStatus

            guard requestedStatus == .authorized else {
                let message = requestedStatus == .denied
                    ? Self.deniedPermissionMessage
                    : Self.unavailablePermissionMessage
                state.captureState = .error(message)
                state.lastErrorMessage = message
                return false
            }

            return true
        }
    }

    private func startASRIfNeeded(
        backend: ASRBackend,
        localASRSettings: LocalASRSettings,
        sourceLanguage: SubtitleLanguage,
        latencyProfile: LatencyProfile
    ) async -> Bool {
        switch backend {
        case .localParakeet:
            activeASRService = parakeetASRService
        case .localWhisperKit:
            activeASRService = whisperKitASRService
        case .mock, .remoteLAN:
            return true
        }

        state.asrDiagnostics.lifecycleState = .loading

        do {
            try await activeASRService.configure(
                ASRConfiguration(
                    sourceLanguage: sourceLanguage.identifier,
                    latencyProfile: latencyProfile,
                    modelID: localASRSettings.activeModelID(for: backend)
                )
            )
            try await activeASRService.start()
            startConsumingASREventsIfNeeded()
            shouldRouteAudioToASR = true
            asrRoutingGeneration += 1
            state.asrDiagnostics.lifecycleState = .ready
            state.asrDiagnostics.lastErrorMessage = nil
            return true
        } catch {
            shouldRouteAudioToASR = false
            state.asrDiagnostics.lifecycleState = .error
            state.asrDiagnostics.lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func startConsumingLevels() {
        levelTask?.cancel()

        let levelSnapshots = captureService.levelSnapshots
        let generation = captureObservationGeneration
        levelTask = Task { @MainActor [weak self] in
            for await snapshot in levelSnapshots {
                guard let self, !Task.isCancelled, self.captureObservationGeneration == generation else { break }
                self.state.lastLevel = snapshot
                if snapshot.peak > 0 || snapshot.rms > 0 {
                    self.clearSilentCaptureWarning()
                    await self.reportAudioActivityIfNeeded()
                }
            }
        }
    }

    private func startConsumingAudioChunks() {
        audioChunkTask?.cancel()

        let audioChunks = captureService.audioChunks
        let generation = captureObservationGeneration
        audioChunkTask = Task { @MainActor [weak self] in
            for await chunk in audioChunks {
                guard let self, !Task.isCancelled, self.captureObservationGeneration == generation else { break }
                var diagnostics = self.state.preprocessingDiagnostics
                if self.serviceEmittedChunkCount == nil {
                    diagnostics.emittedChunkCount += 1
                }
                diagnostics.lastChunkDuration = chunk.duration
                self.state.preprocessingDiagnostics = diagnostics
                self.updateSilentCaptureWarning(for: chunk)
                await self.routeAudioChunkToASRIfNeeded(chunk, captureGeneration: generation)
            }
        }
    }

    private func startConsumingPreprocessingDiagnostics() {
        preprocessingDiagnosticsTask?.cancel()

        let preprocessingDiagnostics = captureService.preprocessingDiagnostics
        let generation = captureObservationGeneration
        preprocessingDiagnosticsTask = Task { @MainActor [weak self] in
            for await snapshot in preprocessingDiagnostics {
                guard let self, !Task.isCancelled, self.captureObservationGeneration == generation else { break }

                var diagnostics = self.state.preprocessingDiagnostics
                self.serviceEmittedChunkCount = snapshot.emittedChunkCount
                diagnostics.emittedChunkCount = snapshot.emittedChunkCount
                diagnostics.lastChunkDuration = snapshot.lastChunkDuration ?? diagnostics.lastChunkDuration
                diagnostics.queueDepthFrames = snapshot.queueDepthFrames
                diagnostics.droppedFrames = snapshot.droppedFrames
                diagnostics.callbackCount = snapshot.callbackCount
                diagnostics.capturedFrameCount = snapshot.capturedFrameCount
                self.state.preprocessingDiagnostics = diagnostics
            }
        }
    }

    private func startConsumingSpeechActivityEvents() {
        speechActivityTask?.cancel()

        let speechActivityEvents = captureService.speechActivityEvents
        let generation = captureObservationGeneration
        speechActivityTask = Task { @MainActor [weak self] in
            for await event in speechActivityEvents {
                guard let self, !Task.isCancelled, self.captureObservationGeneration == generation else { break }

                let shouldUpdateVADFromSpeechEvents = self.serviceVoiceActivityDiagnosticsSeen != true
                var diagnostics = self.state.voiceActivityDiagnostics
                switch event {
                case .speechStarted:
                    if shouldUpdateVADFromSpeechEvents {
                        diagnostics.activityState = .active
                        diagnostics.currentSilenceDuration = 0
                    }
                case .speechChunk(let chunk):
                    await self.reportAudioActivityIfNeeded()
                    if shouldUpdateVADFromSpeechEvents {
                        diagnostics.activityState = .active
                        diagnostics.emittedSpeechChunkCount += 1
                        diagnostics.currentSilenceDuration = 0
                        let level = AudioLevelCalculator.snapshot(
                            samples: chunk.samples,
                            sampleRate: chunk.sampleRate,
                            channelCount: chunk.channelCount
                        )
                        diagnostics.lastChunkRMS = level.rms
                        diagnostics.lastChunkPeak = level.peak
                    }
                case .speechEnded(let metadata):
                    if shouldUpdateVADFromSpeechEvents {
                        diagnostics.activityState = .inactive
                        diagnostics.completedSegmentCount += 1
                        diagnostics.lastSpeechDuration = metadata.duration
                    }
                    await self.flushASRIfNeeded(
                        captureGeneration: generation,
                        routingGeneration: self.asrRoutingGeneration
                    )
                }

                if shouldUpdateVADFromSpeechEvents {
                    self.state.voiceActivityDiagnostics = diagnostics
                }
            }
        }
    }

    private func startConsumingVoiceActivityDiagnostics() {
        voiceActivityDiagnosticsTask?.cancel()

        let voiceActivityDiagnostics = captureService.voiceActivityDiagnostics
        let generation = captureObservationGeneration
        voiceActivityDiagnosticsTask = Task { @MainActor [weak self] in
            for await snapshot in voiceActivityDiagnostics {
                guard let self, !Task.isCancelled, self.captureObservationGeneration == generation else { break }
                self.serviceVoiceActivityDiagnosticsSeen = true
                self.state.voiceActivityDiagnostics = snapshot
            }
        }
    }

    private func startConsumingASREventsIfNeeded() {
        guard asrEventTask == nil else { return }

        asrObservationGeneration += 1

        let events = activeASRService.events
        let generation = asrObservationGeneration
        asrEventTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.asrObservationGeneration == generation {
                    self.asrEventTask = nil
                }
            }

            for await event in events {
                guard let self, !Task.isCancelled, self.asrObservationGeneration == generation else { break }
                switch event {
                case .partial(let segment):
                    self.state.asrDiagnostics.lifecycleState = .transcribing
                    self.state.asrDiagnostics.lastTranscript = segment.text
                case .final(let segment):
                    self.state.asrDiagnostics.lifecycleState = .ready
                    self.state.asrDiagnostics.completedTranscriptCount += 1
                    self.state.asrDiagnostics.lastTranscript = segment.text
                    self.state.asrDiagnostics.lastErrorMessage = nil
                case .error(let message):
                    self.state.asrDiagnostics.lifecycleState = .error
                    self.state.asrDiagnostics.lastErrorMessage = message
                }

                self.forwardEventToSink(event)
            }
        }
    }

    private func forwardEventToSink(_ event: ASREvent) {
        guard asrEventSink != nil else { return }

        if isForwardingEventToSink {
            bufferPendingSinkEvent(event)
            return
        }

        isForwardingEventToSink = true
        Task { @MainActor [weak self] in
            var next: ASREvent? = event
            while let current = next {
                guard let self, let sink = self.asrEventSink else { break }
                await sink(current)
                next = self.dequeuePendingSinkEvent()
            }
            self?.clearPendingSinkEvents()
            self?.isForwardingEventToSink = false
        }
    }

    private func bufferPendingSinkEvent(_ event: ASREvent) {
        switch event {
        case let .final(segment):
            pendingFinalSinkSegments.append(segment)
            if pendingFinalSinkSegments.count > Self.maxPendingSinkSegments {
                pendingFinalSinkSegments.removeFirst(
                    pendingFinalSinkSegments.count - Self.maxPendingSinkSegments
                )
            }
        case .partial, .error:
            pendingOtherSinkEvent = event
        }
    }

    private func dequeuePendingSinkEvent() -> ASREvent? {
        if !pendingFinalSinkSegments.isEmpty {
            let merged = Self.mergedFinalSegment(pendingFinalSinkSegments)
            pendingFinalSinkSegments.removeAll()
            return .final(merged)
        }

        if let other = pendingOtherSinkEvent {
            pendingOtherSinkEvent = nil
            return other
        }

        return nil
    }

    private func clearPendingSinkEvents() {
        pendingFinalSinkSegments.removeAll()
        pendingOtherSinkEvent = nil
    }

    private static func mergedFinalSegment(_ segments: [TranscriptSegment]) -> TranscriptSegment {
        guard segments.count > 1, let first = segments.first, let last = segments.last else {
            return segments[0]
        }

        return TranscriptSegment(
            sourceLanguage: first.sourceLanguage,
            text: segments.map(\.text).joined(separator: " "),
            startTime: first.startTime,
            endTime: last.endTime,
            stability: .final
        )
    }

    private func routeAudioChunkToASRIfNeeded(
        _ chunk: AudioChunk,
        captureGeneration: Int
    ) async {
        let routingGeneration = asrRoutingGeneration
        guard captureObservationGeneration == captureGeneration,
              shouldRouteAudioToASR
        else { return }

        do {
            try await activeASRService.acceptAudioChunk(chunk)
            guard captureObservationGeneration == captureGeneration,
                  asrRoutingGeneration == routingGeneration,
                  shouldRouteAudioToASR
            else { return }
            state.asrDiagnostics.acceptedSpeechChunkCount += 1
            pendingASRDuration += chunk.duration

            if pendingASRDuration >= Self.liveASRAutoFlushDuration {
                await flushASRIfNeeded(
                    captureGeneration: captureGeneration,
                    routingGeneration: routingGeneration
                )
            }
        } catch {
            guard captureObservationGeneration == captureGeneration,
                  asrRoutingGeneration == routingGeneration
            else { return }
            state.asrDiagnostics.lifecycleState = .error
            state.asrDiagnostics.lastErrorMessage = error.localizedDescription
        }
    }

    private func flushASRIfNeeded(
        captureGeneration: Int,
        routingGeneration: Int
    ) async {
        guard captureObservationGeneration == captureGeneration,
              asrRoutingGeneration == routingGeneration,
              shouldRouteAudioToASR
        else { return }
        guard pendingASRDuration > 0 else { return }

        // Never run flushes concurrently: if transcription is slower than the
        // flush cadence, overlapping flushes compound the slowdown. Skipped
        // triggers retry on the next chunk; the ASR services cap their own
        // pending-audio backlog meanwhile.
        guard !isFlushingASR else { return }
        isFlushingASR = true
        defer { isFlushingASR = false }

        state.asrDiagnostics.lifecycleState = .transcribing

        do {
            try await activeASRService.flush()
            guard captureObservationGeneration == captureGeneration,
                  asrRoutingGeneration == routingGeneration
            else { return }
            pendingASRDuration = 0
            if state.asrDiagnostics.lifecycleState != .error {
                state.asrDiagnostics.lifecycleState = .ready
            }
        } catch {
            guard captureObservationGeneration == captureGeneration,
                  asrRoutingGeneration == routingGeneration
            else { return }
            pendingASRDuration = 0
            state.asrDiagnostics.lifecycleState = .error
            state.asrDiagnostics.lastErrorMessage = error.localizedDescription
        }
    }

    private func updateSilentCaptureWarning(for chunk: AudioChunk) {
        let level = AudioLevelCalculator.snapshot(
            samples: chunk.samples,
            sampleRate: chunk.sampleRate,
            channelCount: chunk.channelCount
        )
        guard level.peak == 0 && level.rms == 0 else {
            clearSilentCaptureWarning()
            return
        }

        guard state.captureState.isRunning else { return }
        silentCaptureDuration += chunk.duration
        guard silentCaptureDuration >= Self.silentCaptureWarningDuration else { return }

        state.captureWarningMessage = Self.silentCaptureWarningMessage
    }

    private func clearSilentCaptureWarning() {
        silentCaptureDuration = 0
        state.captureWarningMessage = nil
    }

    private func reportAudioActivityIfNeeded() async {
        guard !hasReportedAudioActivity else { return }
        hasReportedAudioActivity = true
        if let audioActivitySink {
            await audioActivitySink()
        }
    }

    private func startCaptureObservationTasks() {
        captureObservationGeneration += 1
        startConsumingLevels()
        startConsumingAudioChunks()
        startConsumingPreprocessingDiagnostics()
        startConsumingSpeechActivityEvents()
        startConsumingVoiceActivityDiagnostics()
    }

    private func ensureCaptureObservationTasks() {
        if levelTask == nil {
            startConsumingLevels()
        }

        if audioChunkTask == nil {
            startConsumingAudioChunks()
        }

        if preprocessingDiagnosticsTask == nil {
            startConsumingPreprocessingDiagnostics()
        }

        if speechActivityTask == nil {
            startConsumingSpeechActivityEvents()
        }

        if voiceActivityDiagnosticsTask == nil {
            startConsumingVoiceActivityDiagnostics()
        }
    }

    private func cancelCaptureObservationTasks() {
        captureObservationGeneration += 1
        asrObservationGeneration += 1
        levelTask?.cancel()
        levelTask = nil
        audioChunkTask?.cancel()
        audioChunkTask = nil
        preprocessingDiagnosticsTask?.cancel()
        preprocessingDiagnosticsTask = nil
        speechActivityTask?.cancel()
        speechActivityTask = nil
        voiceActivityDiagnosticsTask?.cancel()
        voiceActivityDiagnosticsTask = nil
        asrEventTask?.cancel()
        asrEventTask = nil
    }

    private func cancelCaptureObservationTasksAndWait() async {
        captureObservationGeneration += 1
        asrObservationGeneration += 1

        let tasks = [
            levelTask,
            audioChunkTask,
            preprocessingDiagnosticsTask,
            speechActivityTask,
            voiceActivityDiagnosticsTask,
            asrEventTask
        ]

        levelTask = nil
        audioChunkTask = nil
        preprocessingDiagnosticsTask = nil
        speechActivityTask = nil
        voiceActivityDiagnosticsTask = nil
        asrEventTask = nil

        for task in tasks {
            task?.cancel()
        }

        for task in tasks {
            await task?.value
        }
    }

    private func cancelASREventTaskAndWait() async {
        asrObservationGeneration += 1

        let task = asrEventTask
        asrEventTask = nil
        task?.cancel()
        await task?.value
    }
}
