//
//  AppState.swift
//  LiveSubtitleTranslator
//
//  Created by Christian Merrill on 5/20/26.
//

import Combine

@MainActor
final class AppState: ObservableObject {
    let settingsStore: SettingsStore
    let pipelineController: MockPipelineController
    let subtitleDisplayModel: SubtitleDisplayModel
    let overlayController: SubtitleOverlayWindowController
    let mockSubtitleTicker: MockSubtitleTicker
    let mockASRService: MockASRService
    let mockTranslationService: MockTranslationService
    let appleTranslationService: AppleTranslationService
    let translationLanguageCatalog: AppleTranslationLanguageCatalog
    let whisperKitModelCatalog: WhisperKitModelCatalog
    let translationRouterService: TranslationRouterService
    let metricsRecorder: MetricsRecorder
    let audioDiagnosticsModel: AudioCaptureDiagnosticsModel
    let subtitleCoordinator: SubtitleCoordinator
    let liveSubtitleSessionController: LiveSubtitleSessionController

    init() {
        let settingsStore = SettingsStore()
        let pipelineController = MockPipelineController()
        let subtitleDisplayModel = SubtitleDisplayModel()
        let overlayController = SubtitleOverlayWindowController(
            settingsStore: settingsStore,
            displayModel: subtitleDisplayModel
        )
        let mockSubtitleTicker = MockSubtitleTicker(displayModel: subtitleDisplayModel)
        let mockASRService = MockASRService()
        let mockTranslationService = MockTranslationService()
        let appleTranslationClient = LiveAppleTranslationClient()
        let appleTranslationService = AppleTranslationService(
            client: appleTranslationClient,
            latencyProfileProvider: { settingsStore.settings.latencyProfile }
        )
        let translationLanguageCatalog = AppleTranslationLanguageCatalog(
            client: appleTranslationClient,
            initialSourceLanguage: settingsStore.settings.sourceLanguage,
            initialTargetLanguage: settingsStore.settings.targetLanguage
        )
        let whisperKitModelCatalog = WhisperKitModelCatalog(
            selectedModelID: settingsStore.settings.localASR.modelID
        )
        let translationRouterService = TranslationRouterService(
            settingsStore: settingsStore,
            mockTranslationService: mockTranslationService,
            appleTranslationService: appleTranslationService
        )
        let metricsRecorder = MetricsRecorder()
        let audioDiagnosticsModel = AudioCaptureDiagnosticsModel()
        let subtitleCoordinator = SubtitleCoordinator(
            settingsStore: settingsStore,
            displayModel: subtitleDisplayModel,
            asrService: mockASRService,
            translationService: translationRouterService,
            metricsRecorder: metricsRecorder
        )
        let liveSubtitleSessionController = LiveSubtitleSessionController(
            settingsStore: settingsStore,
            overlayController: overlayController,
            audioDiagnosticsModel: audioDiagnosticsModel,
            subtitleCoordinator: subtitleCoordinator
        )

        self.settingsStore = settingsStore
        self.pipelineController = pipelineController
        self.subtitleDisplayModel = subtitleDisplayModel
        self.overlayController = overlayController
        self.mockSubtitleTicker = mockSubtitleTicker
        self.mockASRService = mockASRService
        self.mockTranslationService = mockTranslationService
        self.appleTranslationService = appleTranslationService
        self.translationLanguageCatalog = translationLanguageCatalog
        self.whisperKitModelCatalog = whisperKitModelCatalog
        self.translationRouterService = translationRouterService
        self.metricsRecorder = metricsRecorder
        self.audioDiagnosticsModel = audioDiagnosticsModel
        self.subtitleCoordinator = subtitleCoordinator
        self.liveSubtitleSessionController = liveSubtitleSessionController
    }

    init(settingsStore: SettingsStore, pipelineController: MockPipelineController) {
        let subtitleDisplayModel = SubtitleDisplayModel()
        let overlayController = SubtitleOverlayWindowController(
            settingsStore: settingsStore,
            displayModel: subtitleDisplayModel
        )
        let mockSubtitleTicker = MockSubtitleTicker(displayModel: subtitleDisplayModel)
        let mockASRService = MockASRService()
        let mockTranslationService = MockTranslationService()
        let appleTranslationClient = LiveAppleTranslationClient()
        let appleTranslationService = AppleTranslationService(
            client: appleTranslationClient,
            latencyProfileProvider: { settingsStore.settings.latencyProfile }
        )
        let translationLanguageCatalog = AppleTranslationLanguageCatalog(
            client: appleTranslationClient,
            initialSourceLanguage: settingsStore.settings.sourceLanguage,
            initialTargetLanguage: settingsStore.settings.targetLanguage
        )
        let whisperKitModelCatalog = WhisperKitModelCatalog(
            selectedModelID: settingsStore.settings.localASR.modelID
        )
        let translationRouterService = TranslationRouterService(
            settingsStore: settingsStore,
            mockTranslationService: mockTranslationService,
            appleTranslationService: appleTranslationService
        )
        let metricsRecorder = MetricsRecorder()
        let audioDiagnosticsModel = AudioCaptureDiagnosticsModel()
        let subtitleCoordinator = SubtitleCoordinator(
            settingsStore: settingsStore,
            displayModel: subtitleDisplayModel,
            asrService: mockASRService,
            translationService: translationRouterService,
            metricsRecorder: metricsRecorder
        )
        let liveSubtitleSessionController = LiveSubtitleSessionController(
            settingsStore: settingsStore,
            overlayController: overlayController,
            audioDiagnosticsModel: audioDiagnosticsModel,
            subtitleCoordinator: subtitleCoordinator
        )

        self.settingsStore = settingsStore
        self.pipelineController = pipelineController
        self.subtitleDisplayModel = subtitleDisplayModel
        self.overlayController = overlayController
        self.mockSubtitleTicker = mockSubtitleTicker
        self.mockASRService = mockASRService
        self.mockTranslationService = mockTranslationService
        self.appleTranslationService = appleTranslationService
        self.translationLanguageCatalog = translationLanguageCatalog
        self.whisperKitModelCatalog = whisperKitModelCatalog
        self.translationRouterService = translationRouterService
        self.metricsRecorder = metricsRecorder
        self.audioDiagnosticsModel = audioDiagnosticsModel
        self.subtitleCoordinator = subtitleCoordinator
        self.liveSubtitleSessionController = liveSubtitleSessionController
    }
}
