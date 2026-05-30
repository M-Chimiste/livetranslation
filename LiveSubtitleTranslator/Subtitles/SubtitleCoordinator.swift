//
//  SubtitleCoordinator.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import Combine
import Foundation

@MainActor
final class SubtitleCoordinator: ObservableObject {
    @Published private(set) var pipelineState: PipelineState = .idle
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var handledASREventCount = 0
    @Published private(set) var translationAttemptCount = 0
    @Published private(set) var translationSuccessCount = 0
    @Published private(set) var lastTranscriptText: String?
    @Published private(set) var lastTranslationText: String?

    private let settingsStore: SettingsStore
    private let displayModel: SubtitleDisplayModel
    private let asrService: ASRService
    private let translationService: TranslationService
    private let metricsRecorder: MetricsRecorder
    private let lineWrapper: SubtitleLineWrapper
    private let subtitleHoldDuration: Duration

    private var stabilizer: SubtitleStabilizer
    private var eventTask: Task<Void, Never>?
    private var holdTask: Task<Void, Never>?
    private var displayedTranslationID: UUID?
    private var isExternalEventMode = false
    private var hasExternalAudioActivity = false

    init(
        settingsStore: SettingsStore,
        displayModel: SubtitleDisplayModel,
        asrService: ASRService,
        translationService: TranslationService,
        metricsRecorder: MetricsRecorder,
        lineWrapper: SubtitleLineWrapper = .default,
        stabilizer: SubtitleStabilizer = SubtitleStabilizer(),
        subtitleHoldDuration: Duration = .milliseconds(3_500)
    ) {
        self.settingsStore = settingsStore
        self.displayModel = displayModel
        self.asrService = asrService
        self.translationService = translationService
        self.metricsRecorder = metricsRecorder
        self.lineWrapper = lineWrapper
        self.stabilizer = stabilizer
        self.subtitleHoldDuration = subtitleHoldDuration
    }

    func start() async {
        guard !pipelineState.isRunning else { return }

        resetDiagnostics()
        isExternalEventMode = false
        pipelineState = .listening

        do {
            try await asrService.configure(
                ASRConfiguration(
                    sourceLanguage: settingsStore.settings.sourceLanguage.identifier,
                    latencyProfile: settingsStore.settings.latencyProfile
                )
            )

            startConsumingASREvents()
            try await asrService.start()
        } catch {
            pipelineState = .error
            lastErrorMessage = error.localizedDescription
        }
    }

    func startExternalEvents(status: SubtitleOverlayStatus? = nil) async {
        guard !pipelineState.isRunning else { return }

        eventTask?.cancel()
        eventTask = nil
        holdTask?.cancel()
        holdTask = nil
        displayedTranslationID = nil
        hasExternalAudioActivity = false
        stabilizer.reset()
        displayModel.clear()
        resetDiagnostics()
        if let status {
            displayModel.showStatus(status)
        }
        isExternalEventMode = true
        pipelineState = .listening
    }

    func showOverlayStatus(_ status: SubtitleOverlayStatus) {
        guard status != .listening || !hasExternalAudioActivity else { return }
        displayModel.showStatus(status)
    }

    func noteExternalAudioActivity() {
        guard isExternalEventMode else { return }
        hasExternalAudioActivity = true
        displayModel.clearStatus()
    }

    func reportExternalEventStartupError(_ message: String) {
        eventTask?.cancel()
        eventTask = nil
        holdTask?.cancel()
        holdTask = nil
        displayedTranslationID = nil
        hasExternalAudioActivity = false
        stabilizer.reset()
        displayModel.clear()
        displayModel.showStatus(.error)
        resetDiagnostics()
        lastErrorMessage = message
        isExternalEventMode = false
        pipelineState = .error
    }

    func stop() async {
        eventTask?.cancel()
        eventTask = nil

        holdTask?.cancel()
        holdTask = nil
        displayedTranslationID = nil
        hasExternalAudioActivity = false

        await asrService.stop()
        stabilizer.reset()
        displayModel.clear()
        resetDiagnostics()
        isExternalEventMode = false
        pipelineState = .idle
    }

    func stopExternalEvents() async {
        eventTask?.cancel()
        eventTask = nil
        holdTask?.cancel()
        holdTask = nil
        displayedTranslationID = nil
        hasExternalAudioActivity = false
        stabilizer.reset()
        displayModel.clear()
        resetDiagnostics()
        isExternalEventMode = false
        pipelineState = .idle
    }

    func handleASREvent(_ event: ASREvent) async {
        let wasRunning = pipelineState.isRunning || isExternalEventMode
        handledASREventCount += 1

        switch event {
        case let .partial(segment):
            lastTranscriptText = segment.text
            metricsRecorder.record(.asrPartialReceived, segmentID: segment.id)

            guard segment.stability == .stablePartial else {
                returnToPriorRunningState(wasRunning: wasRunning)
                return
            }

            await translateAndDisplay(segment: segment, isPartial: true, wasRunning: wasRunning)

        case let .final(segment):
            lastTranscriptText = segment.text
            metricsRecorder.record(.asrFinalReceived, segmentID: segment.id)
            await translateAndDisplay(segment: segment, isPartial: false, wasRunning: wasRunning)

        case let .error(message):
            pipelineState = .error
            lastErrorMessage = message
        }
    }

    private func startConsumingASREvents() {
        eventTask?.cancel()

        let events = asrService.events
        eventTask = Task { [weak self] in
            for await event in events {
                if Task.isCancelled { break }
                await self?.handleASREvent(event)
            }
        }
    }

    private func translateAndDisplay(
        segment: TranscriptSegment,
        isPartial: Bool,
        wasRunning: Bool
    ) async {
        pipelineState = .translating

        do {
            let context = stabilizer.context()
            translationAttemptCount += 1
            metricsRecorder.record(.translationStarted, segmentID: segment.id)

            let translation = try await translationService.translate(
                segment: segment,
                context: context,
                targetLanguage: settingsStore.settings.targetLanguage
            )

            metricsRecorder.record(.translationFinished, segmentID: segment.id)
            lastErrorMessage = nil
            translationSuccessCount += 1
            lastTranslationText = translation.translatedText

            if !isPartial {
                stabilizer.recordFinalSegment(segment)
            }

            guard stabilizer.shouldDisplay(
                translatedText: translation.translatedText,
                isPartial: isPartial
            ) else {
                returnToPriorRunningState(wasRunning: wasRunning)
                return
            }

            display(translation: translation, isPartial: isPartial)
            returnToPriorRunningState(wasRunning: wasRunning)
        } catch {
            pipelineState = .error
            lastErrorMessage = error.localizedDescription
            displayModel.showStatus(.error)
        }
    }

    private func display(translation: TranslationSegment, isPartial: Bool) {
        let wrappedLines = lineWrapper.wrap(translation.translatedText)
        guard let primaryLine = wrappedLines.first else { return }

        displayedTranslationID = translation.id
        displayModel.update(
            SubtitleDisplayState(
                primaryLine: primaryLine,
                secondaryLine: wrappedLines.dropFirst().first,
                isPartial: isPartial
            )
        )
        metricsRecorder.record(.overlayRendered, segmentID: translation.transcriptID)

        if !isPartial {
            scheduleHoldClear(for: translation.id)
        }
    }

    private func scheduleHoldClear(for translationID: UUID) {
        holdTask?.cancel()

        let subtitleHoldDuration = self.subtitleHoldDuration
        holdTask = Task { [weak self] in
            do {
                try await Task.sleep(for: subtitleHoldDuration)
            } catch {
                return
            }

            await MainActor.run {
                guard self?.displayedTranslationID == translationID else { return }
                self?.displayedTranslationID = nil
                self?.displayModel.clear()
                if self?.isExternalEventMode == true,
                   self?.pipelineState.isRunning == true,
                   self?.hasExternalAudioActivity == false {
                    self?.displayModel.showStatus(.listening)
                }
            }
        }
    }

    private func returnToPriorRunningState(wasRunning: Bool) {
        pipelineState = wasRunning ? .listening : .idle
    }

    private func resetDiagnostics() {
        lastErrorMessage = nil
        handledASREventCount = 0
        translationAttemptCount = 0
        translationSuccessCount = 0
        lastTranscriptText = nil
        lastTranslationText = nil
    }
}
