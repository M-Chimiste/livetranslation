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
    let nllbTranslationService: NLLBTranslationService
    let hunyuanTranslationService: HunyuanMTTranslationService
    let translationLanguageCatalog: AppleTranslationLanguageCatalog
    let parakeetModelCatalog: ParakeetModelCatalog
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
        let parakeetModelCatalog = ParakeetModelCatalog(
            selectedModelID: settingsStore.settings.localASR.modelID
        )
        let nllbTranslationService = NLLBTranslationService()
        let hunyuanTranslationService = HunyuanMTTranslationService()
        let translationRouterService = TranslationRouterService(
            settingsStore: settingsStore,
            mockTranslationService: mockTranslationService,
            appleTranslationService: appleTranslationService,
            nllbTranslationService: nllbTranslationService,
            hunyuanTranslationService: hunyuanTranslationService
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
            subtitleCoordinator: subtitleCoordinator,
            nllbTranslationService: nllbTranslationService,
            hunyuanTranslationService: hunyuanTranslationService
        )

        self.settingsStore = settingsStore
        self.pipelineController = pipelineController
        self.subtitleDisplayModel = subtitleDisplayModel
        self.overlayController = overlayController
        self.mockSubtitleTicker = mockSubtitleTicker
        self.mockASRService = mockASRService
        self.mockTranslationService = mockTranslationService
        self.appleTranslationService = appleTranslationService
        self.nllbTranslationService = nllbTranslationService
        self.hunyuanTranslationService = hunyuanTranslationService
        self.translationLanguageCatalog = translationLanguageCatalog
        self.parakeetModelCatalog = parakeetModelCatalog
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
        let parakeetModelCatalog = ParakeetModelCatalog(
            selectedModelID: settingsStore.settings.localASR.modelID
        )
        let nllbTranslationService = NLLBTranslationService()
        let hunyuanTranslationService = HunyuanMTTranslationService()
        let translationRouterService = TranslationRouterService(
            settingsStore: settingsStore,
            mockTranslationService: mockTranslationService,
            appleTranslationService: appleTranslationService,
            nllbTranslationService: nllbTranslationService,
            hunyuanTranslationService: hunyuanTranslationService
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
            subtitleCoordinator: subtitleCoordinator,
            nllbTranslationService: nllbTranslationService,
            hunyuanTranslationService: hunyuanTranslationService
        )

        self.settingsStore = settingsStore
        self.pipelineController = pipelineController
        self.subtitleDisplayModel = subtitleDisplayModel
        self.overlayController = overlayController
        self.mockSubtitleTicker = mockSubtitleTicker
        self.mockASRService = mockASRService
        self.mockTranslationService = mockTranslationService
        self.appleTranslationService = appleTranslationService
        self.nllbTranslationService = nllbTranslationService
        self.hunyuanTranslationService = hunyuanTranslationService
        self.translationLanguageCatalog = translationLanguageCatalog
        self.parakeetModelCatalog = parakeetModelCatalog
        self.translationRouterService = translationRouterService
        self.metricsRecorder = metricsRecorder
        self.audioDiagnosticsModel = audioDiagnosticsModel
        self.subtitleCoordinator = subtitleCoordinator
        self.liveSubtitleSessionController = liveSubtitleSessionController
    }
}
