//
//  LiveSubtitleSessionController.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/21/26.
//

import Combine
import Foundation

enum LiveSubtitleSessionState: Equatable {
    case idle
    case starting
    case running
    case stopping
    case error(String)

    var displayName: String {
        switch self {
        case .idle:
            "Idle"
        case .starting:
            "Starting"
        case .running:
            "Running"
        case .stopping:
            "Stopping"
        case .error(let message):
            "Error: \(message)"
        }
    }

    var isActive: Bool {
        switch self {
        case .starting, .running, .stopping:
            true
        case .idle, .error:
            false
        }
    }
}

@MainActor
final class LiveSubtitleSessionController: ObservableObject {
    @Published private(set) var state: LiveSubtitleSessionState = .idle

    private let settingsStore: SettingsStore
    private let overlayController: SubtitleOverlayWindowController
    private let audioDiagnosticsModel: AudioCaptureDiagnosticsModel
    private let subtitleCoordinator: SubtitleCoordinator
    private let nllbTranslationService: NLLBTranslationService?
    private let hunyuanTranslationService: HunyuanMTTranslationService?
    private var captureWasRunningBeforeStart = false

    init(
        settingsStore: SettingsStore,
        overlayController: SubtitleOverlayWindowController,
        audioDiagnosticsModel: AudioCaptureDiagnosticsModel,
        subtitleCoordinator: SubtitleCoordinator,
        nllbTranslationService: NLLBTranslationService? = nil,
        hunyuanTranslationService: HunyuanMTTranslationService? = nil
    ) {
        self.settingsStore = settingsStore
        self.overlayController = overlayController
        self.audioDiagnosticsModel = audioDiagnosticsModel
        self.subtitleCoordinator = subtitleCoordinator
        self.nllbTranslationService = nllbTranslationService
        self.hunyuanTranslationService = hunyuanTranslationService
    }

    func start() async {
        guard !state.isActive else { return }
        captureWasRunningBeforeStart = false

        if let validationError = validationError(for: settingsStore.settings) {
            state = .error(validationError)
            audioDiagnosticsModel.reportSessionError(validationError)
            overlayController.show()
            subtitleCoordinator.reportExternalEventStartupError(validationError)
            return
        }

        state = .starting
        captureWasRunningBeforeStart = audioDiagnosticsModel.state.captureState.isRunning

        // Warm the local translation model in parallel with capture/ASR startup so
        // the first subtitle isn't stalled by the one-time model load.
        switch settingsStore.settings.translationBackend {
        case .localNLLB:
            if let nllbTranslationService { Task { await nllbTranslationService.warmUp() } }
        case .localHunyuanMT:
            if let hunyuanTranslationService { Task { await hunyuanTranslationService.warmUp() } }
        default:
            break
        }

        await subtitleCoordinator.stop()
        overlayController.show()
        await subtitleCoordinator.startExternalEvents(status: .preparingLiveSubtitles)

        audioDiagnosticsModel.asrEventSink = { [weak subtitleCoordinator] event in
            await subtitleCoordinator?.handleASREvent(event)
        }
        audioDiagnosticsModel.audioActivitySink = { [weak subtitleCoordinator] in
            subtitleCoordinator?.noteExternalAudioActivity()
        }

        await audioDiagnosticsModel.startCapture(
            audioSourceOption: settingsStore.settings.audioSource,
            voiceActivitySettings: settingsStore.settings.voiceActivity,
            asrBackend: settingsStore.settings.asrBackend,
            localASRSettings: settingsStore.settings.localASR,
            sourceLanguage: settingsStore.settings.sourceLanguage,
            latencyProfile: settingsStore.settings.latencyProfile,
            requiresASR: true
        )

        guard audioDiagnosticsModel.state.captureState.isRunning,
              audioDiagnosticsModel.state.asrDiagnostics.lifecycleState == .ready
        else {
            let message = audioDiagnosticsModel.state.asrDiagnostics.lastErrorMessage
                ?? audioDiagnosticsModel.state.lastErrorMessage
                ?? "Live subtitle capture failed."
            audioDiagnosticsModel.asrEventSink = nil
            audioDiagnosticsModel.audioActivitySink = nil
            subtitleCoordinator.reportExternalEventStartupError(message)
            state = .error(message)
            captureWasRunningBeforeStart = false
            return
        }

        subtitleCoordinator.showOverlayStatus(.listening)
        state = .running
    }

    func stop() async {
        guard state.isActive || audioDiagnosticsModel.state.captureState.isRunning else { return }

        state = .stopping
        audioDiagnosticsModel.asrEventSink = nil
        audioDiagnosticsModel.audioActivitySink = nil
        if captureWasRunningBeforeStart {
            await audioDiagnosticsModel.stopASRRouting()
        } else {
            await audioDiagnosticsModel.stopCapture()
        }
        await subtitleCoordinator.stopExternalEvents()
        captureWasRunningBeforeStart = false
        state = .idle
    }

    private func validationError(for settings: AppSettings) -> String? {
        if settings.audioSource != .systemOutput {
            return "Live subtitles require System Output audio source for this phase."
        }

        if settings.asrBackend != .localParakeet, settings.asrBackend != .localWhisperKit {
            return "Live subtitles require a local ASR backend (Parakeet or WhisperKit)."
        }

        if settings.translationBackend == .remoteLAN {
            return "Live subtitles do not support Remote LAN translation yet."
        }

        return nil
    }
}
