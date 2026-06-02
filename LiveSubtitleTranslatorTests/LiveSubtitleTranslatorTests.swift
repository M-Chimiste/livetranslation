//
//  LiveSubtitleTranslatorTests.swift
//  LiveSubtitleTranslatorTests
//
//  Created by Christian Merrill on 5/20/26.
//

import CoreAudio
import Foundation
import Testing
@testable import LiveSubtitleTranslator

@MainActor
private final class FakeAudioCaptureService: AudioCaptureService {
    private nonisolated struct CaptureStreams {
        let audioChunks: AsyncStream<AudioChunk>
        let levelSnapshots: AsyncStream<AudioLevelSnapshot>
        let preprocessingDiagnostics: AsyncStream<AudioPreprocessingDiagnostics>
        let speechActivityEvents: AsyncStream<SpeechActivityEvent>
        let voiceActivityDiagnostics: AsyncStream<VoiceActivityDiagnostics>

        let audioChunkContinuation: AsyncStream<AudioChunk>.Continuation
        let levelContinuation: AsyncStream<AudioLevelSnapshot>.Continuation
        let preprocessingDiagnosticsContinuation: AsyncStream<AudioPreprocessingDiagnostics>.Continuation
        let speechActivityContinuation: AsyncStream<SpeechActivityEvent>.Continuation
        let voiceActivityDiagnosticsContinuation: AsyncStream<VoiceActivityDiagnostics>.Continuation

        static func make() -> CaptureStreams {
            let audioChunkStream = AsyncStream<AudioChunk>.makeStream()
            let levelStream = AsyncStream<AudioLevelSnapshot>.makeStream()
            let preprocessingDiagnosticsStream = AsyncStream<AudioPreprocessingDiagnostics>.makeStream()
            let speechActivityStream = AsyncStream<SpeechActivityEvent>.makeStream()
            let voiceActivityDiagnosticsStream = AsyncStream<VoiceActivityDiagnostics>.makeStream()

            return CaptureStreams(
                audioChunks: audioChunkStream.stream,
                levelSnapshots: levelStream.stream,
                preprocessingDiagnostics: preprocessingDiagnosticsStream.stream,
                speechActivityEvents: speechActivityStream.stream,
                voiceActivityDiagnostics: voiceActivityDiagnosticsStream.stream,
                audioChunkContinuation: audioChunkStream.continuation,
                levelContinuation: levelStream.continuation,
                preprocessingDiagnosticsContinuation: preprocessingDiagnosticsStream.continuation,
                speechActivityContinuation: speechActivityStream.continuation,
                voiceActivityDiagnosticsContinuation: voiceActivityDiagnosticsStream.continuation
            )
        }

        func finish() {
            audioChunkContinuation.finish()
            levelContinuation.finish()
            preprocessingDiagnosticsContinuation.finish()
            speechActivityContinuation.finish()
            voiceActivityDiagnosticsContinuation.finish()
        }
    }

    var state: AudioCaptureState = .idle
    var audioChunks: AsyncStream<AudioChunk> { streams.audioChunks }
    var levelSnapshots: AsyncStream<AudioLevelSnapshot> { streams.levelSnapshots }
    var preprocessingDiagnostics: AsyncStream<AudioPreprocessingDiagnostics> { streams.preprocessingDiagnostics }
    var speechActivityEvents: AsyncStream<SpeechActivityEvent> { streams.speechActivityEvents }
    var voiceActivityDiagnostics: AsyncStream<VoiceActivityDiagnostics> { streams.voiceActivityDiagnostics }
    var sources: [AudioSource]
    var availableSourcesError: Error?
    var startError: Error?
    var onStart: (@MainActor () async -> Void)?
    var lastVoiceActivitySettings: VoiceActivitySettings?
    var startRequests: [AudioSource] = []
    var stopCount = 0
    private var streams = CaptureStreams.make()

    init(sources: [AudioSource] = [.systemOutput]) {
        self.sources = sources
    }

    deinit {
        streams.finish()
    }

    func updateVoiceActivitySettings(_ settings: VoiceActivitySettings) {
        lastVoiceActivitySettings = settings
    }

    func availableSources() async throws -> [AudioSource] {
        if let availableSourcesError {
            throw availableSourcesError
        }

        return sources
    }

    func start(source: AudioSource) async throws {
        startRequests.append(source)
        streams.finish()
        streams = CaptureStreams.make()

        if let onStart {
            await onStart()
        }

        if let startError {
            state = .error(startError.localizedDescription)
            throw startError
        }

        state = .capturing
    }

    func stop() async {
        stopCount += 1
        state = .idle
        streams.finish()
    }

    func emitLevel(_ snapshot: AudioLevelSnapshot) {
        streams.levelContinuation.yield(snapshot)
    }

    func emitChunk(_ chunk: AudioChunk) {
        streams.audioChunkContinuation.yield(chunk)
    }

    func emitPreprocessingDiagnostics(_ snapshot: AudioPreprocessingDiagnostics) {
        streams.preprocessingDiagnosticsContinuation.yield(snapshot)
    }

    func emitSpeechActivityEvent(_ event: SpeechActivityEvent) {
        streams.speechActivityContinuation.yield(event)
    }

    func emitVoiceActivityDiagnostics(_ snapshot: VoiceActivityDiagnostics) {
        streams.voiceActivityDiagnosticsContinuation.yield(snapshot)
    }
}

@MainActor
private final class FakeAudioCapturePermissionProvider: AudioCapturePermissionProviding {
    var status: AudioCapturePermissionStatus
    var requestedStatus: AudioCapturePermissionStatus
    var requestCount = 0

    init(
        status: AudioCapturePermissionStatus,
        requestedStatus: AudioCapturePermissionStatus? = nil
    ) {
        self.status = status
        self.requestedStatus = requestedStatus ?? status
    }

    func currentStatus() -> AudioCapturePermissionStatus {
        status
    }

    func requestPermission() async -> AudioCapturePermissionStatus {
        requestCount += 1
        status = requestedStatus
        return requestedStatus
    }
}

private enum FakeParakeetTranscriberError: LocalizedError {
    case transcriptionFailed

    var errorDescription: String? {
        "Fake Parakeet transcription failed."
    }
}

private enum FakeASRServiceError: LocalizedError {
    case modelLoadFailed

    var errorDescription: String? {
        "Fake ASR model load failed."
    }
}

private actor FakeParakeetTranscriber: ParakeetTranscribing {
    var loadedModelIDs: [String] = []
    var transcribedSamples: [[Float]] = []
    var output = ParakeetTranscriptionOutput(text: "Hello from Parakeet")
    var transcriptionError: Error?

    func load(modelID: String) async throws {
        if loadedModelIDs.last != modelID {
            loadedModelIDs.append(modelID)
        }
    }

    func transcribe(samples: [Float]) async throws -> ParakeetTranscriptionOutput {
        if let transcriptionError {
            throw transcriptionError
        }

        transcribedSamples.append(samples)
        return output
    }

    func setTranscriptionError(_ error: Error?) {
        transcriptionError = error
    }
}

private actor FakeWhisperKitTranscriber: WhisperKitTranscribing {
    var loadedModelIDs: [String] = []
    var transcribedLanguages: [String] = []
    var output = WhisperKitTranscriptionOutput(text: "Hello from WhisperKit")

    func load(modelID: String) async throws {
        if loadedModelIDs.last != modelID {
            loadedModelIDs.append(modelID)
        }
    }

    func transcribe(samples: [Float], language: String) async throws -> WhisperKitTranscriptionOutput {
        transcribedLanguages.append(language)
        return output
    }
}

@MainActor
private final class FakeAppleTranslationClient: AppleTranslationClient {
    struct AvailabilityRequest: Equatable, Hashable {
        let source: String
        let target: String
    }

    struct TranslateRequest: Equatable {
        let text: String
        let configuration: AppleTranslationClientConfiguration
        let shouldPrepare: Bool
    }

    var availabilityStatus: AppleTranslationAvailabilityStatus = .installed
    var supportedLanguageIdentifiersValue = ["en", "zh-Hans", "zh-Hant"]
    var availabilityStatusesByRequest: [AvailabilityRequest: AppleTranslationAvailabilityStatus] = [:]
    var translatedText = "你好"
    var translationError: Error?
    private(set) var availabilityRequests: [AvailabilityRequest] = []
    private(set) var translateRequests: [TranslateRequest] = []

    func supportedLanguageIdentifiers() async -> [String] {
        supportedLanguageIdentifiersValue
    }

    func availabilityStatus(
        from sourceLanguageIdentifier: String,
        to targetLanguageIdentifier: String
    ) async -> AppleTranslationAvailabilityStatus {
        let request = AvailabilityRequest(
            source: sourceLanguageIdentifier,
            target: targetLanguageIdentifier
        )
        availabilityRequests.append(
            request
        )
        return availabilityStatusesByRequest[request] ?? availabilityStatus
    }

    func translate(
        _ text: String,
        configuration: AppleTranslationClientConfiguration,
        shouldPrepare: Bool
    ) async throws -> String {
        translateRequests.append(
            TranslateRequest(
                text: text,
                configuration: configuration,
                shouldPrepare: shouldPrepare
            )
        )

        if let translationError {
            throw translationError
        }

        return translatedText
    }
}

@MainActor
private final class RecordingTranslationService: TranslationService {
    struct Request: Equatable {
        let segment: TranscriptSegment
        let context: [TranscriptSegment]
        let targetLanguage: SubtitleLanguage
    }

    var translatedText: String
    var error: Error?
    private(set) var requests: [Request] = []

    init(translatedText: String, error: Error? = nil) {
        self.translatedText = translatedText
        self.error = error
    }

    func translate(
        segment: TranscriptSegment,
        context: [TranscriptSegment],
        targetLanguage: SubtitleLanguage
    ) async throws -> TranslationSegment {
        requests.append(
            Request(
                segment: segment,
                context: context,
                targetLanguage: targetLanguage
            )
        )

        if let error {
            throw error
        }

        return TranslationSegment(
            transcriptID: segment.id,
            sourceText: segment.text,
            translatedText: translatedText,
            targetLanguage: targetLanguage
        )
    }
}

@MainActor
private final class FakeASRService: ASRService {
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

    var events: AsyncStream<ASREvent> { eventStream.events }
    var configuration: ASRConfiguration = .defaults
    var isRunning = false
    var acceptedAudioChunks: [AudioChunk] = []
    var startCount = 0
    var flushCount = 0
    var stopCount = 0
    var finalEventOnFlush: ASREvent?
    var startError: Error?
    private var eventStream = EventStream.make()
    private var shouldRenewEventStreamOnStart = false

    init() {}

    deinit {
        eventStream.finish()
    }

    func configure(_ configuration: ASRConfiguration) async throws {
        self.configuration = configuration
    }

    func start() async throws {
        if let startError {
            throw startError
        }
        if shouldRenewEventStreamOnStart {
            eventStream.finish()
            eventStream = EventStream.make()
            shouldRenewEventStreamOnStart = false
        }
        startCount += 1
        isRunning = true
    }

    func acceptAudioChunk(_ chunk: AudioChunk) async throws {
        guard isRunning else { return }
        acceptedAudioChunks.append(chunk)
    }

    func flush() async throws {
        flushCount += 1
        if let finalEventOnFlush {
            eventStream.continuation.yield(finalEventOnFlush)
        }
    }

    func stop() async {
        stopCount += 1
        isRunning = false
        acceptedAudioChunks.removeAll()
        eventStream.finish()
        shouldRenewEventStreamOnStart = true
    }

    func emit(_ event: ASREvent) {
        eventStream.continuation.yield(event)
    }
}

struct LiveSubtitleTranslatorTests {
    @MainActor
    private func makeIsolatedSettingsStore(
        storageKey: String = "settings"
    ) throws -> (SettingsStore, String) {
        let suiteName = "LiveSubtitleTranslatorTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        let store = SettingsStore(userDefaults: userDefaults, storageKey: storageKey)

        return (store, suiteName)
    }

    private func makeTranscriptSegment(
        _ text: String,
        stability: TranscriptSegment.Stability,
        id: UUID = UUID(),
        sourceLanguage: String = "en",
        startTime: TimeInterval = 0,
        endTime: TimeInterval = 1
    ) -> TranscriptSegment {
        TranscriptSegment(
            id: id,
            sourceLanguage: sourceLanguage,
            text: text,
            startTime: startTime,
            endTime: endTime,
            createdAt: Date(timeIntervalSince1970: 100),
            stability: stability,
            confidence: 0.95
        )
    }

    private func makeAudioChunk(
        rms: Float,
        duration: TimeInterval = 1,
        startHostTime: UInt64 = 0
    ) -> AudioChunk {
        let sampleRate = 16_000.0
        let sampleCount = Int(sampleRate * duration)

        return AudioChunk(
            captureStartHostTime: startHostTime,
            captureEndHostTime: startHostTime + UInt64(duration * 1_000),
            sampleRate: sampleRate,
            channelCount: 1,
            samples: Array(repeating: rms, count: sampleCount)
        )
    }

    @MainActor
    @Test
    func appSettingsDefaultsAreDeterministic() {
        let settings = AppSettings.defaults

        #expect(settings.audioSource == .systemOutput)
        #expect(settings.asrBackend == .localParakeet)
        #expect(settings.translationBackend == .appleTranslation)
        #expect(settings.sourceLanguage == .english)
        #expect(settings.targetLanguage == .simplifiedChinese)
        #expect(settings.latencyProfile == .balanced)
        #expect(settings.diagnosticsEnabled)
        #expect(settings.remoteServerURL == nil)
        #expect(settings.overlay == .defaults)
        #expect(settings.overlay.isLocked)
        #expect(settings.overlay.frame.width == 1_200)
        #expect(settings.overlay.frame.height == 160)
        #expect(settings.voiceActivity == .defaults)
        #expect(settings.voiceActivity.sensitivity == .balanced)
        #expect(settings.voiceActivity.finalSilenceDuration == 1.0)
        #expect(settings.localASR == .defaults)
        #expect(settings.localASR.modelID == LocalASRSettings.parakeetV3ModelID)
    }

    @Test
    func backendPickerOptionsHideInternalMockBackends() {
        #expect(ASRBackend.userSelectableCases == [.localParakeet, .localWhisperKit, .remoteLAN])
        #expect(TranslationBackend.userSelectableCases == [.appleTranslation, .localNLLB, .localHunyuanMT, .remoteLAN])
        #expect(!ASRBackend.userSelectableCases.contains(.mock))
        #expect(!TranslationBackend.userSelectableCases.contains(.mock))
    }

    @Test
    func appSettingsMigratesLegacyMockBackendsToLiveDefaults() throws {
        let legacyData = try #require("""
        {
          "asrBackend": "mock",
          "translationBackend": "mock"
        }
        """.data(using: .utf8))

        let decodedSettings = try JSONDecoder().decode(AppSettings.self, from: legacyData)

        #expect(decodedSettings.asrBackend == .localParakeet)
        #expect(decodedSettings.translationBackend == .appleTranslation)
    }

    @MainActor
    @Test
    func settingsStoreRoundTripsThroughIsolatedUserDefaults() throws {
        let (store, suiteName) = try makeIsolatedSettingsStore()
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        let storageKey = "settings"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        store.settings.audioSource = .selectedApp
        store.settings.asrBackend = .localParakeet
        store.settings.translationBackend = .appleTranslation
        store.settings.sourceLanguage = SubtitleLanguage("ja")
        store.settings.targetLanguage = .traditionalChinese
        store.settings.latencyProfile = .moreAccurate
        store.settings.diagnosticsEnabled = false
        store.settings.remoteServerURL = URL(string: "ws://192.168.1.10:8765")
        store.settings.overlay.frame = OverlayFrame(x: 20, y: 40, width: 640, height: 120)
        store.settings.overlay.isLocked = false
        store.settings.voiceActivity = VoiceActivitySettings(
            sensitivity: .high,
            finalSilenceDuration: 0.7
        )
        store.settings.localASR = LocalASRSettings(
            modelID: LocalASRSettings.parakeetV2ModelID
        )

        let reloadedStore = SettingsStore(userDefaults: userDefaults, storageKey: storageKey)

        #expect(reloadedStore.settings == store.settings)
    }

    @Test
    func voiceActivitySettingsRoundTripsThroughCodable() throws {
        let settings = VoiceActivitySettings(
            sensitivity: .low,
            finalSilenceDuration: 1.4
        )

        let data = try JSONEncoder().encode(settings)
        let decodedSettings = try JSONDecoder().decode(VoiceActivitySettings.self, from: data)

        #expect(decodedSettings == settings)
        #expect(VADSensitivity.high.thresholds.startRMS == 0.008)
        #expect(VADSensitivity.balanced.thresholds.continueRMS == 0.008)
        #expect(VADSensitivity.low.thresholds.startRMS == 0.030)
    }

    @Test
    func localASRSettingsAndConfigurationRoundTripDefaults() throws {
        let settings = LocalASRSettings(modelID: LocalASRSettings.parakeetV2ModelID)

        let data = try JSONEncoder().encode(settings)
        let decodedSettings = try JSONDecoder().decode(LocalASRSettings.self, from: data)

        #expect(decodedSettings == settings)
        #expect(LocalASRSettings.defaults.modelID == LocalASRSettings.parakeetV3ModelID)
        #expect(LocalASRSettings.availableModelIDs == [
            LocalASRSettings.parakeetV3ModelID,
            LocalASRSettings.parakeetV2ModelID
        ])
        #expect(LocalASRSettings.displayName(for: LocalASRSettings.parakeetV2ModelID) == "Parakeet v2 (English)")
        #expect(LocalASRSettings.displayName(for: LocalASRSettings.parakeetV3ModelID) == "Parakeet v3 (multilingual)")
        #expect(ASRConfiguration.defaults.modelID == LocalASRSettings.parakeetV3ModelID)

        // WhisperKit selection round-trips independently and has its own catalog/display.
        #expect(LocalASRSettings.defaults.whisperKitModelID == LocalASRSettings.whisperLargeV3ModelID)
        #expect(LocalASRSettings.whisperKitModelIDs == [
            LocalASRSettings.whisperLargeV3ModelID,
            LocalASRSettings.whisperLargeV3TurboModelID,
            LocalASRSettings.whisperTinyModelID
        ])
        #expect(LocalASRSettings.whisperKitDisplayName(for: LocalASRSettings.whisperTinyModelID) == "Whisper tiny")
        #expect(LocalASRSettings.canonicalWhisperKitModelID(for: "tiny") == LocalASRSettings.whisperTinyModelID)

        let perBackend = LocalASRSettings(
            modelID: LocalASRSettings.parakeetV2ModelID,
            whisperKitModelID: LocalASRSettings.whisperTinyModelID
        )
        #expect(perBackend.activeModelID(for: .localParakeet) == LocalASRSettings.parakeetV2ModelID)
        #expect(perBackend.activeModelID(for: .localWhisperKit) == LocalASRSettings.whisperTinyModelID)

        let configuration = ASRConfiguration(
            sourceLanguage: "en",
            latencyProfile: .fast,
            modelID: LocalASRSettings.parakeetV2ModelID
        )

        #expect(configuration.sourceLanguage == "en")
        #expect(configuration.latencyProfile == .fast)
        #expect(configuration.modelID == LocalASRSettings.parakeetV2ModelID)

        // The persisted Parakeet field still migrates any legacy Whisper IDs to v3.
        let legacyTinyData = try #require(#"{"modelID":"openai_whisper-tiny"}"#.data(using: .utf8))
        let decodedLegacyTiny = try JSONDecoder().decode(LocalASRSettings.self, from: legacyTinyData)
        #expect(decodedLegacyTiny.modelID == LocalASRSettings.parakeetV3ModelID)

        // ASRConfiguration no longer force-canonicalizes; the service does it per family.
        #expect(
            ASRConfiguration(
                sourceLanguage: "en",
                latencyProfile: .balanced,
                modelID: "openai_whisper-tiny"
            ).modelID == "openai_whisper-tiny"
        )
    }

    @MainActor
    @Test
    func appSettingsDecodesLegacySettingsWithoutOverlayFields() throws {
        let legacyData = try #require("""
        {
          "audioSource": "selectedApp",
          "asrBackend": "localParakeet",
          "translationBackend": "appleTranslation",
          "targetLanguage": "zh-Hant",
          "latencyProfile": "moreAccurate",
          "diagnosticsEnabled": false,
          "remoteServerURL": "ws://192.168.1.10:8765"
        }
        """.data(using: .utf8))

        let decodedSettings = try JSONDecoder().decode(AppSettings.self, from: legacyData)

        #expect(decodedSettings.audioSource == .selectedApp)
        #expect(decodedSettings.asrBackend == .localParakeet)
        #expect(decodedSettings.translationBackend == .appleTranslation)
        #expect(decodedSettings.sourceLanguage == .english)
        #expect(decodedSettings.targetLanguage == .traditionalChinese)
        #expect(decodedSettings.latencyProfile == .moreAccurate)
        #expect(decodedSettings.diagnosticsEnabled == false)
        #expect(decodedSettings.remoteServerURL == URL(string: "ws://192.168.1.10:8765"))
        #expect(decodedSettings.overlay == .defaults)
        #expect(decodedSettings.voiceActivity == .defaults)
        #expect(decodedSettings.localASR == .defaults)
    }

    @MainActor
    @Test
    func mockPipelineStartStopIsIdempotent() {
        let controller = MockPipelineController()

        #expect(controller.state == .idle)

        controller.start()
        controller.start()
        #expect(controller.state == .listening)

        controller.stop()
        controller.stop()
        #expect(controller.state == .idle)
    }

    @MainActor
    @Test
    func corePipelineModelsCanBeConstructed() {
        let audioChunk = AudioChunk(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            captureStartHostTime: 10,
            captureEndHostTime: 20,
            sampleRate: 16_000,
            channelCount: 1,
            samples: [0.1, -0.1]
        )

        #expect(audioChunk.sampleRate == 16_000)
        #expect(audioChunk.channelCount == 1)
        #expect(AudioSource.systemOutput.kind == .systemOutput)
        #expect(ASRConfiguration.defaults.sourceLanguage == "en")
        #expect(ASRConfiguration.defaults.latencyProfile == .balanced)
        #expect(ASRConfiguration.defaults.modelID == LocalASRSettings.parakeetV3ModelID)
    }

    @Test
    func subtitleLanguageSupportsArbitraryIdentifiersAndWhisperCodes() throws {
        let japanese = SubtitleLanguage("ja-JP")
        let french = SubtitleLanguage("fr")

        let data = try JSONEncoder().encode(japanese)
        let decoded = try JSONDecoder().decode(SubtitleLanguage.self, from: data)

        #expect(decoded == japanese)
        #expect(french.identifier == "fr")
        #expect(french.displayName == "French")
        #expect(SubtitleLanguage.simplifiedChinese.displayName == "Simplified Chinese")
        #expect(SubtitleLanguage.traditionalChinese.displayName == "Traditional Chinese")
        #expect(SubtitleLanguage("zh-Hans").whisperLanguageCode == "zh")
        #expect(SubtitleLanguage("es-419").whisperLanguageCode == "es")
    }

    @MainActor
    @Test
    func appleTranslationLanguageCatalogFiltersTargetsForSelectedSource() async {
        let client = FakeAppleTranslationClient()
        client.supportedLanguageIdentifiersValue = ["fr", "en", "zh-Hans", "ja"]
        client.availabilityStatus = .unsupported
        client.availabilityStatusesByRequest = [
            FakeAppleTranslationClient.AvailabilityRequest(source: "ja", target: "en"): .installed,
            FakeAppleTranslationClient.AvailabilityRequest(source: "ja", target: "zh-Hans"): .supported
        ]
        let catalog = AppleTranslationLanguageCatalog(client: client)

        let selectedTarget = await catalog.refresh(
            sourceLanguage: SubtitleLanguage("ja"),
            selectedTargetLanguage: SubtitleLanguage("fr")
        )

        #expect(catalog.sourceLanguages.contains(.english))
        #expect(catalog.sourceLanguages.contains(SubtitleLanguage("ja")))
        #expect(!catalog.targetLanguages.contains(SubtitleLanguage("ja")))
        #expect(catalog.targetLanguages == [.simplifiedChinese, .english])
        #expect(selectedTarget == .simplifiedChinese)
        #expect(catalog.statusMessage == nil)
    }

    @MainActor
    @Test
    func appleTranslationLanguageCatalogPreservesValidTargetsAndFallsBackWhenEmpty() async {
        let client = FakeAppleTranslationClient()
        client.supportedLanguageIdentifiersValue = []
        client.availabilityStatus = .unsupported
        let catalog = AppleTranslationLanguageCatalog(client: client)

        let selectedTarget = await catalog.refresh(
            sourceLanguage: .english,
            selectedTargetLanguage: .traditionalChinese
        )

        #expect(catalog.sourceLanguages.contains(.english))
        #expect(catalog.targetLanguages == [.simplifiedChinese, .traditionalChinese])
        #expect(selectedTarget == .traditionalChinese)
        #expect(catalog.statusMessage != nil)
    }

    @MainActor
    @Test
    func parakeetModelCatalogExposesAvailableVersions() async {
        let catalog = ParakeetModelCatalog(
            selectedModelID: LocalASRSettings.parakeetV3ModelID
        )

        #expect(catalog.modelIDs == [
            LocalASRSettings.parakeetV3ModelID,
            LocalASRSettings.parakeetV2ModelID
        ])
        #expect(catalog.modelIDs.first == LocalASRSettings.parakeetV3ModelID)
        #expect(!catalog.isRefreshing)

        await catalog.refresh(selectedModelID: LocalASRSettings.parakeetV2ModelID)

        #expect(catalog.modelIDs.contains(LocalASRSettings.parakeetV2ModelID))
        #expect(catalog.modelIDs.contains(LocalASRSettings.parakeetV3ModelID))
    }

    @MainActor
    @Test
    func audioCaptureDiagnosticsDefaultsAreStatusOnlyPlaceholders() {
        let state = AudioCaptureDiagnosticsState.placeholder
        let model = AudioCaptureDiagnosticsModel(
            captureService: FakeAudioCaptureService(),
            permissionProvider: StaticAudioCapturePermissionProvider(status: .notRequested)
        )

        #expect(state.permissionStatus == .notRequested)
        #expect(state.permissionStatus.displayName == "Not Requested")
        #expect(state.captureState == .idle)
        #expect(state.captureState.displayName == "Idle")
        #expect(state.sourceAvailability == .placeholderOnly)
        #expect(state.sourceAvailability.displayName == "Placeholder Only")
        #expect(state.preprocessingDiagnostics == .zero)
        #expect(state.preprocessingDiagnostics.emittedChunkCountDisplayValue == "0")
        #expect(state.preprocessingDiagnostics.lastChunkDurationDisplayValue == "None")
        #expect(state.preprocessingDiagnostics.queueDepthDisplayValue == "0")
        #expect(state.preprocessingDiagnostics.droppedFramesDisplayValue == "0")
        #expect(state.preprocessingDiagnostics.callbackCountDisplayValue == "0")
        #expect(state.preprocessingDiagnostics.capturedFrameCountDisplayValue == "0")
        #expect(state.voiceActivityDiagnostics == .zero)
        #expect(state.voiceActivityDiagnostics.activityStateDisplayValue == "Inactive")
        #expect(state.voiceActivityDiagnostics.emittedSpeechChunkCountDisplayValue == "0")
        #expect(state.voiceActivityDiagnostics.completedSegmentCountDisplayValue == "0")
        #expect(state.voiceActivityDiagnostics.lastSpeechDurationDisplayValue == "None")
        #expect(state.asrDiagnostics == .placeholder)
        #expect(state.asrDiagnostics.lifecycleStateDisplayValue == "Idle")
        #expect(state.asrDiagnostics.modelID == LocalASRSettings.parakeetV3ModelID)
        #expect(state.asrDiagnostics.lastTranscriptDisplayValue == "None")
        #expect(model.state == state)
    }

    @Test
    func audioLevelCalculatorCoversSilenceKnownValuesAndNegativeSamples() {
        let empty = AudioLevelCalculator.snapshot(
            samples: [],
            timestamp: Date(timeIntervalSince1970: 1),
            sampleRate: 48_000,
            channelCount: 1
        )
        #expect(empty.rms == 0)
        #expect(empty.peak == 0)
        #expect(empty.rmsDecibels == -.infinity)
        #expect(empty.rmsDisplayValue == "0.000 (-∞ dBFS)")

        let known = AudioLevelCalculator.snapshot(
            samples: [1, -1, 0, 0],
            timestamp: Date(timeIntervalSince1970: 2),
            sampleRate: 48_000,
            channelCount: 1
        )

        #expect(abs(known.rms - Float(sqrt(0.5))) < 0.0001)
        #expect(known.peak == 1)
        #expect(known.sampleRate == 48_000)
        #expect(known.channelCount == 1)
        #expect(known.peakDisplayValue == "1.000 (0.0 dBFS)")
    }

    @MainActor
    @Test
    func audioSourceProcessMetadataConstructionIsDeterministic() {
        let source = AudioSource(
            id: "process-42",
            displayName: "Safari",
            kind: .process,
            processObjectID: 42,
            processID: 1234,
            bundleID: "com.apple.Safari"
        )

        #expect(source.id == "process-42")
        #expect(source.displayName == "Safari")
        #expect(source.kind == .process)
        #expect(source.processObjectID == 42)
        #expect(source.processID == 1234)
        #expect(source.bundleID == "com.apple.Safari")
    }

    @Test
    func processTapAggregateDescriptionUsesTapOnlyInput() {
        let description = ProcessTapAudioCaptureService.makeAggregateDeviceDescription(
            aggregateUID: "aggregate-uid"
        )

        #expect(description[kAudioAggregateDeviceUIDKey] as? String == "aggregate-uid")
        #expect(description[kAudioAggregateDeviceIsPrivateKey] as? Bool == true)
        #expect(description[kAudioAggregateDeviceIsStackedKey] as? Bool == false)
        #expect(description[kAudioAggregateDeviceMainSubDeviceKey] == nil)
        #expect(description[kAudioAggregateDeviceTapAutoStartKey] == nil)

        let subDevices = description[kAudioAggregateDeviceSubDeviceListKey] as? [Any]
        #expect(subDevices?.isEmpty == true)
        #expect(description[kAudioAggregateDeviceTapListKey] == nil)
    }

    @Test
    func processTapDescriptionUsesSystemDefaultOutput() {
        let tapUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000014")!
        let description = ProcessTapAudioCaptureService.makeSystemOutputTapDescription(
            tapUUID: tapUUID
        )

        #expect(description.uuid == tapUUID)
        #expect(description.isPrivate)
        #expect(description.muteBehavior == .unmuted)
        #expect(description.deviceUID == nil)
        #expect(description.stream == 0)
        #expect(description.isExclusive)
        #expect(description.isMixdown)
        #expect(!description.isMono)
    }

    @Test
    func audioRingBufferPreservesOrderWrapsAndReportsOverflow() {
        let buffer = AudioRingBuffer(capacityFrames: 4, channelCount: 1, sampleRate: 4)

        buffer.write(
            interleavedSamples: [1, 2, 3],
            captureStartHostTime: 10,
            captureEndHostTime: 12
        )
        let firstRead = buffer.read(maxFrames: 2)

        #expect(firstRead.samples == [1, 2])
        #expect(firstRead.frameCount == 2)
        #expect(buffer.diagnostics.queueDepthFrames == 1)

        buffer.write(
            interleavedSamples: [4, 5, 6, 7],
            captureStartHostTime: 13,
            captureEndHostTime: 16
        )
        let secondRead = buffer.read(maxFrames: 10)

        #expect(secondRead.samples == [4, 5, 6, 7])
        #expect(secondRead.frameCount == 4)
        #expect(buffer.diagnostics.droppedFrames == 1)

        buffer.reset()

        #expect(buffer.diagnostics.queueDepthFrames == 0)
        #expect(buffer.diagnostics.droppedFrames == 0)
        #expect(buffer.read(maxFrames: 1).isEmpty)
    }

    @Test
    func audioRingBufferKeepsInterleavedStereoFramesTogether() {
        let buffer = AudioRingBuffer(capacityFrames: 3, channelCount: 2, sampleRate: 48_000)

        buffer.write(
            interleavedSamples: [1, 10, 2, 20, 3, 30],
            captureStartHostTime: 100,
            captureEndHostTime: 300
        )

        let read = buffer.read(maxFrames: 3)

        #expect(read.samples == [1, 10, 2, 20, 3, 30])
        #expect(read.frameCount == 3)
        #expect(read.channelCount == 2)
        #expect(read.sampleRate == 48_000)
    }

    @Test
    func audioResamplerConverts48kMonoTo16kMono() throws {
        let sourceSamples = (0..<48_000).map { index in
            Float(sin(Double(index) * 0.01))
        }
        let resampler = AudioResampler(sourceSampleRate: 48_000, sourceChannelCount: 1)

        let outputSamples = try resampler.convert(interleavedSamples: sourceSamples)

        #expect(outputSamples.count == 16_000)
    }

    @Test
    func audioResamplerMixesStereoToMonoAndHandlesEmptyInput() throws {
        let resampler = AudioResampler(sourceSampleRate: 16_000, sourceChannelCount: 2)

        let mixedSamples = try resampler.convert(interleavedSamples: [1, -1, 0.5, 0.25])
        let emptySamples = try resampler.convert(interleavedSamples: [])

        #expect(mixedSamples == [0, 0.375])
        #expect(emptySamples.isEmpty)
    }

    @Test
    func audioChunkAssemblerEmitsOneSecondChunksAndCarriesRemainder() {
        var assembler = AudioChunkAssembler(sampleRate: 4, channelCount: 1, chunkDuration: 1)

        let initialChunks = assembler.append(
            samples: [1, 2, 3],
            captureStartHostTime: 100,
            captureEndHostTime: 300
        )
        let laterChunks = assembler.append(
            samples: [4, 5, 6],
            captureStartHostTime: 400,
            captureEndHostTime: 600
        )

        #expect(initialChunks.isEmpty)
        #expect(laterChunks.count == 1)
        #expect(laterChunks.first?.samples == [1, 2, 3, 4])
        #expect(laterChunks.first?.sampleRate == 4)
        #expect(laterChunks.first?.channelCount == 1)
        #expect(laterChunks.first?.duration == 1)
        #expect(laterChunks.first?.captureStartHostTime == 100)
        #expect(laterChunks.first?.captureEndHostTime == 400)
        #expect(assembler.pendingSampleCount == 2)
    }

    @Test
    func audioChunkAssemblerResetDiscardsPartialCarryover() {
        var assembler = AudioChunkAssembler(sampleRate: 4, channelCount: 1, chunkDuration: 1)

        _ = assembler.append(
            samples: [1, 2, 3],
            captureStartHostTime: 100,
            captureEndHostTime: 300
        )
        assembler.reset()

        let chunks = assembler.append(
            samples: [9, 10, 11, 12],
            captureStartHostTime: 900,
            captureEndHostTime: 1_200
        )

        #expect(chunks.count == 1)
        #expect(chunks.first?.samples == [9, 10, 11, 12])
        #expect(assembler.pendingSampleCount == 0)
    }

    @Test
    func energyVoiceActivityDetectorSuppressesSilence() {
        var detector = EnergyVoiceActivityDetector(settings: .defaults)

        let events = detector.process(makeAudioChunk(rms: 0))

        #expect(events.isEmpty)
        #expect(detector.currentDiagnostics.activityState == .inactive)
        #expect(detector.currentDiagnostics.currentSilenceDuration == 1)
        #expect(detector.currentDiagnostics.emittedSpeechChunkCount == 0)
    }

    @Test
    func energyVoiceActivityDetectorStartsOnFirstSpeechChunk() throws {
        var detector = EnergyVoiceActivityDetector(settings: .defaults)

        let chunk = makeAudioChunk(rms: 0.02, startHostTime: 100)
        let events = detector.process(chunk)

        #expect(events.count == 2)
        if case let .speechStarted(metadata) = try #require(events.first) {
            #expect(metadata.captureStartHostTime == 100)
            #expect(metadata.chunkCount == 1)
        } else {
            Issue.record("Expected speechStarted")
        }
        #expect(events.last == .speechChunk(chunk))
        #expect(detector.currentDiagnostics.activityState == .active)
        #expect(detector.currentDiagnostics.emittedSpeechChunkCount == 1)
        #expect(abs(detector.currentDiagnostics.lastChunkRMS - 0.02) < 0.0001)
    }

    @Test
    func energyVoiceActivityDetectorEndsAfterFinalSilence() throws {
        var detector = EnergyVoiceActivityDetector(settings: .defaults)

        _ = detector.process(makeAudioChunk(rms: 0.02, startHostTime: 100))
        let events = detector.process(makeAudioChunk(rms: 0, startHostTime: 1_100))

        #expect(events.count == 1)
        if case let .speechEnded(metadata) = try #require(events.first) {
            #expect(metadata.chunkCount == 1)
            #expect(metadata.duration == 1)
            #expect(metadata.captureEndHostTime == 1_100)
            #expect(abs(metadata.rms - 0.02) < 0.0001)
        } else {
            Issue.record("Expected speechEnded")
        }
        #expect(detector.currentDiagnostics.activityState == .inactive)
        #expect(detector.currentDiagnostics.completedSegmentCount == 1)
        #expect(detector.currentDiagnostics.lastSpeechDuration == 1)
    }

    @Test
    func energyVoiceActivityDetectorContinuesWhenSpeechResumesBeforeFinalSilence() {
        let settings = VoiceActivitySettings(
            sensitivity: .balanced,
            finalSilenceDuration: 2
        )
        var detector = EnergyVoiceActivityDetector(settings: settings)

        _ = detector.process(makeAudioChunk(rms: 0.02, startHostTime: 100))
        #expect(detector.process(makeAudioChunk(rms: 0, startHostTime: 1_100)).isEmpty)
        let resumedEvents = detector.process(makeAudioChunk(rms: 0.01, startHostTime: 2_100))

        #expect(resumedEvents.count == 1)
        if case .speechChunk = resumedEvents.first {
            #expect(true)
        } else {
            Issue.record("Expected continued speechChunk")
        }
        #expect(detector.currentDiagnostics.completedSegmentCount == 0)
        #expect(detector.currentDiagnostics.emittedSpeechChunkCount == 2)
        #expect(detector.currentDiagnostics.currentSilenceDuration == 0)
    }

    @Test
    func energyVoiceActivityDetectorSensitivityThresholdsAreDeterministic() {
        var highSensitivity = EnergyVoiceActivityDetector(
            settings: VoiceActivitySettings(sensitivity: .high, finalSilenceDuration: 1)
        )
        var balancedSensitivity = EnergyVoiceActivityDetector(
            settings: VoiceActivitySettings(sensitivity: .balanced, finalSilenceDuration: 1)
        )
        var lowSensitivity = EnergyVoiceActivityDetector(
            settings: VoiceActivitySettings(sensitivity: .low, finalSilenceDuration: 1)
        )

        #expect(!highSensitivity.process(makeAudioChunk(rms: 0.009)).isEmpty)
        #expect(balancedSensitivity.process(makeAudioChunk(rms: 0.009)).isEmpty)
        #expect(lowSensitivity.process(makeAudioChunk(rms: 0.02)).isEmpty)
    }

    @Test
    func energyVoiceActivityDetectorResetDiscardsActiveSpeech() {
        var detector = EnergyVoiceActivityDetector(settings: .defaults)

        _ = detector.process(makeAudioChunk(rms: 0.02))
        detector.reset()
        #expect(detector.currentDiagnostics == .zero)

        let eventsAfterReset = detector.process(makeAudioChunk(rms: 0))

        #expect(eventsAfterReset.isEmpty)
    }

    @MainActor
    @Test
    func audioCaptureDiagnosticsRefreshesSourcesStartsStopsAndTracksLevels() async {
        let processSource = AudioSource(
            id: "process-99",
            displayName: "Test Player",
            kind: .process,
            processObjectID: 99,
            processID: 9090,
            bundleID: "com.example.player"
        )
        let service = FakeAudioCaptureService(sources: [.systemOutput, processSource])
        let model = AudioCaptureDiagnosticsModel(captureService: service)

        await model.refreshSources()

        #expect(model.state.sourceAvailability == .available)
        #expect(model.state.availableSources == [.systemOutput, processSource])
        #expect(model.state.sourceCountDisplayValue == "2")

        let vadSettings = VoiceActivitySettings(
            sensitivity: .high,
            finalSilenceDuration: 0.5
        )
        await model.startCapture(
            audioSourceOption: .systemOutput,
            voiceActivitySettings: vadSettings
        )

        #expect(service.startRequests == [.systemOutput])
        #expect(service.lastVoiceActivitySettings == vadSettings)
        #expect(model.state.captureState == .capturing)
        #expect(model.state.permissionStatus == .authorized)

        let level = AudioLevelSnapshot(
            rms: 0.25,
            peak: 0.5,
            timestamp: Date(timeIntervalSince1970: 3),
            sampleRate: 48_000,
            channelCount: 1
        )
        service.emitLevel(level)
        for _ in 0..<20 where model.state.lastLevel != level {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(model.state.lastLevel == level)

        await model.stopCapture()

        #expect(service.stopCount == 1)
        #expect(model.state.captureState == .idle)
        #expect(model.state.lastLevel == .zero)
        #expect(model.state.preprocessingDiagnostics == .zero)
        #expect(model.state.voiceActivityDiagnostics == .zero)
    }

    @MainActor
    @Test
    func audioCaptureDiagnosticsRequestsPermissionAndBlocksDeniedCapture() async {
        let deniedService = FakeAudioCaptureService()
        let deniedPermission = FakeAudioCapturePermissionProvider(status: .denied)
        let deniedModel = AudioCaptureDiagnosticsModel(
            captureService: deniedService,
            permissionProvider: deniedPermission
        )

        await deniedModel.startCapture(audioSourceOption: .systemOutput)

        #expect(deniedPermission.requestCount == 0)
        #expect(deniedService.startRequests.isEmpty)
        #expect(deniedModel.state.permissionStatus == .denied)
        if case .error = deniedModel.state.captureState {
        } else {
            Issue.record("Expected denied capture to enter error state.")
        }
        #expect(deniedModel.state.lastErrorMessage?.contains("System audio recording permission is denied") == true)
        #expect(deniedModel.state.lastErrorMessage?.contains("Screen & System Audio Recording") == true)

        let requestedService = FakeAudioCaptureService()
        let requestedPermission = FakeAudioCapturePermissionProvider(
            status: .notRequested,
            requestedStatus: .authorized
        )
        let requestedModel = AudioCaptureDiagnosticsModel(
            captureService: requestedService,
            permissionProvider: requestedPermission
        )

        await requestedModel.startCapture(audioSourceOption: .systemOutput)

        #expect(requestedPermission.requestCount == 1)
        #expect(requestedService.startRequests == [.systemOutput])
        #expect(requestedModel.state.permissionStatus == .authorized)
        #expect(requestedModel.state.captureState == .capturing)
    }

    @MainActor
    @Test
    func audioCaptureDiagnosticsTracksChunksAndPreprocessingCounters() async {
        let service = FakeAudioCaptureService()
        let model = AudioCaptureDiagnosticsModel(captureService: service)

        await model.startCapture(audioSourceOption: .systemOutput)

        let chunk = AudioChunk(
            captureStartHostTime: 10,
            captureEndHostTime: 20,
            sampleRate: 16_000,
            channelCount: 1,
            samples: Array(repeating: 0.1, count: 16_000)
        )
        service.emitChunk(chunk)
        service.emitPreprocessingDiagnostics(
            AudioPreprocessingDiagnostics(
                emittedChunkCount: 1,
                lastChunkDuration: 1,
                queueDepthFrames: 480,
                droppedFrames: 3,
                callbackCount: 12,
                capturedFrameCount: 5_760
            )
        )

        for _ in 0..<20
            where model.state.preprocessingDiagnostics.queueDepthFrames != 480
        {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(model.state.preprocessingDiagnostics.emittedChunkCount == 1)
        #expect(model.state.preprocessingDiagnostics.lastChunkDuration == 1)
        #expect(model.state.preprocessingDiagnostics.queueDepthFrames == 480)
        #expect(model.state.preprocessingDiagnostics.droppedFrames == 3)
        #expect(model.state.preprocessingDiagnostics.callbackCount == 12)
        #expect(model.state.preprocessingDiagnostics.capturedFrameCount == 5_760)

        await model.stopCapture()

        #expect(model.state.preprocessingDiagnostics == .zero)
    }

    @MainActor
    @Test
    func audioCaptureDiagnosticsWarnsWhenChunksRemainSilent() async {
        let service = FakeAudioCaptureService()
        let model = AudioCaptureDiagnosticsModel(captureService: service)

        await model.startCapture(audioSourceOption: .systemOutput)

        for index in 0..<5 {
            service.emitChunk(
                AudioChunk(
                    captureStartHostTime: UInt64(index * 1_000),
                    captureEndHostTime: UInt64((index + 1) * 1_000),
                    sampleRate: 16_000,
                    channelCount: 1,
                    samples: Array(repeating: 0, count: 16_000)
                )
            )
        }

        for _ in 0..<40 where model.state.captureWarningMessage == nil {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(model.state.captureWarningMessage?.contains("No captured audio detected") == true)

        service.emitLevel(
            AudioLevelSnapshot(
                rms: 0.02,
                peak: 0.03,
                timestamp: Date(timeIntervalSince1970: 4),
                sampleRate: 48_000,
                channelCount: 2
            )
        )

        for _ in 0..<40 where model.state.captureWarningMessage != nil {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(model.state.captureWarningMessage == nil)

        await model.stopCapture()
    }

    @MainActor
    @Test
    func audioCaptureDiagnosticsTracksSpeechActivityEventsAndVADDiagnostics() async {
        let service = FakeAudioCaptureService()
        let model = AudioCaptureDiagnosticsModel(captureService: service)

        await model.startCapture(audioSourceOption: .systemOutput)

        let chunk = makeAudioChunk(rms: 0.02, startHostTime: 20)
        let metadata = SpeechSegmentMetadata(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            captureStartHostTime: 20,
            captureEndHostTime: 1_020,
            chunkCount: 1,
            duration: 1,
            peak: 0.02,
            rms: 0.02
        )
        service.emitSpeechActivityEvent(.speechStarted(metadata))
        service.emitSpeechActivityEvent(.speechChunk(chunk))
        service.emitSpeechActivityEvent(.speechEnded(metadata))

        for _ in 0..<20
            where model.state.voiceActivityDiagnostics.completedSegmentCount != 1
        {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(model.state.voiceActivityDiagnostics.activityState == .inactive)
        #expect(model.state.voiceActivityDiagnostics.emittedSpeechChunkCount == 1)
        #expect(model.state.voiceActivityDiagnostics.completedSegmentCount == 1)
        #expect(model.state.voiceActivityDiagnostics.lastSpeechDuration == 1)

        service.emitVoiceActivityDiagnostics(
            VoiceActivityDiagnostics(
                activityState: .active,
                completedSegmentCount: 2,
                emittedSpeechChunkCount: 3,
                lastSpeechDuration: 1.5,
                currentSilenceDuration: 0.25,
                lastChunkRMS: 0.03,
                lastChunkPeak: 0.04
            )
        )

        for _ in 0..<20
            where model.state.voiceActivityDiagnostics.completedSegmentCount != 2
        {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(model.state.voiceActivityDiagnostics.activityState == .active)
        #expect(model.state.voiceActivityDiagnostics.emittedSpeechChunkCount == 3)
        #expect(model.state.voiceActivityDiagnostics.completedSegmentCount == 2)
        #expect(model.state.voiceActivityDiagnostics.currentSilenceDuration == 0.25)
        #expect(model.state.voiceActivityDiagnostics.lastChunkRMS == 0.03)
        #expect(model.state.voiceActivityDiagnostics.lastChunkPeak == 0.04)

        await model.stopCapture()

        #expect(model.state.voiceActivityDiagnostics == .zero)
    }

    @MainActor
    @Test
    func audioCaptureDiagnosticsRoutesContinuousAudioChunksToLocalASRDiagnostics() async {
        let captureService = FakeAudioCaptureService()
        let asrService = FakeASRService()
        let model = AudioCaptureDiagnosticsModel(
            captureService: captureService,
            asrService: asrService
        )
        let chunk = makeAudioChunk(rms: 0.02, startHostTime: 20)
        let segment = TranscriptSegment(
            sourceLanguage: "en",
            text: "A real transcript",
            startTime: 0,
            endTime: 1,
            stability: .final,
            confidence: 0.9
        )
        let metadata = SpeechSegmentMetadata(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            captureStartHostTime: 20,
            captureEndHostTime: 1_020,
            chunkCount: 1,
            duration: 1,
            peak: 0.02,
            rms: 0.02
        )
        asrService.finalEventOnFlush = .final(segment)

        await model.startCapture(
            audioSourceOption: .systemOutput,
            voiceActivitySettings: .defaults,
            asrBackend: .localParakeet,
            localASRSettings: LocalASRSettings(modelID: LocalASRSettings.parakeetV3ModelID),
            sourceLanguage: SubtitleLanguage("ja"),
            latencyProfile: .fast
        )

        #expect(asrService.isRunning)
        #expect(asrService.configuration.sourceLanguage == "ja")
        #expect(asrService.configuration.latencyProfile == .fast)
        #expect(asrService.configuration.modelID == LocalASRSettings.parakeetV3ModelID)
        #expect(model.state.asrDiagnostics.lifecycleState == .ready)

        captureService.emitChunk(chunk)
        for _ in 0..<1_000 where asrService.acceptedAudioChunks.isEmpty {
            try? await Task.sleep(for: .milliseconds(1))
        }
        captureService.emitSpeechActivityEvent(.speechEnded(metadata))

        for _ in 0..<40
            where model.state.asrDiagnostics.completedTranscriptCount != 1
        {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(asrService.acceptedAudioChunks == [chunk])
        #expect(asrService.flushCount == 1)
        #expect(model.state.asrDiagnostics.acceptedSpeechChunkCount == 1)
        #expect(model.state.asrDiagnostics.completedTranscriptCount == 1)
        #expect(model.state.asrDiagnostics.lastTranscript == "A real transcript")

        await model.stopCapture()

        #expect(asrService.stopCount == 1)
        #expect(model.state.asrDiagnostics.lifecycleState == .idle)
        #expect(model.state.asrDiagnostics.acceptedSpeechChunkCount == 0)
    }

    @MainActor
    @Test
    func audioCaptureDiagnosticsAutoFlushesOngoingAudioForLiveASR() async {
        let captureService = FakeAudioCaptureService()
        let asrService = FakeASRService()
        let model = AudioCaptureDiagnosticsModel(
            captureService: captureService,
            asrService: asrService
        )
        let metadata = SpeechSegmentMetadata(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            captureStartHostTime: 20,
            captureEndHostTime: 3_020,
            chunkCount: 3,
            duration: 3,
            peak: 0.02,
            rms: 0.02
        )
        let firstChunk = makeAudioChunk(rms: 0.02, startHostTime: 20)
        let secondChunk = makeAudioChunk(rms: 0.02, startHostTime: 1_020)
        let thirdChunk = makeAudioChunk(rms: 0.02, startHostTime: 2_020)
        asrService.finalEventOnFlush = .final(
            makeTranscriptSegment("Periodic transcript", stability: .final)
        )

        await model.startCapture(
            audioSourceOption: .systemOutput,
            voiceActivitySettings: .defaults,
            asrBackend: .localParakeet,
            localASRSettings: .defaults,
            latencyProfile: .balanced
        )

        captureService.emitSpeechActivityEvent(.speechStarted(metadata))
        captureService.emitChunk(firstChunk)
        captureService.emitChunk(secondChunk)

        try? await Task.sleep(for: .milliseconds(10))
        #expect(asrService.flushCount == 0)

        captureService.emitChunk(thirdChunk)

        for _ in 0..<40
            where model.state.asrDiagnostics.completedTranscriptCount != 1
        {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(asrService.acceptedAudioChunks == [firstChunk, secondChunk, thirdChunk])
        #expect(asrService.flushCount == 1)
        #expect(model.state.asrDiagnostics.acceptedSpeechChunkCount == 3)
        #expect(model.state.asrDiagnostics.completedTranscriptCount == 1)
        #expect(model.state.asrDiagnostics.lastTranscript == "Periodic transcript")

        await model.stopCapture()
    }

    @MainActor
    @Test
    func audioCaptureDiagnosticsForwardsASREventsThroughSingleSink() async {
        let captureService = FakeAudioCaptureService()
        let asrService = FakeASRService()
        let model = AudioCaptureDiagnosticsModel(
            captureService: captureService,
            asrService: asrService
        )
        var forwardedEvents: [ASREvent] = []
        let segment = makeTranscriptSegment("Forward me", stability: .final)

        model.asrEventSink = { event in
            forwardedEvents.append(event)
        }

        await model.startCapture(
            audioSourceOption: .systemOutput,
            asrBackend: .localParakeet
        )
        asrService.emit(.final(segment))

        for _ in 0..<40 where forwardedEvents.isEmpty {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(model.state.asrDiagnostics.completedTranscriptCount == 1)
        #expect(forwardedEvents == [.final(segment)])

        await model.stopCapture()

        #expect(model.asrEventSink == nil)
    }

    @MainActor
    @Test
    func audioCaptureDiagnosticsAttachesLocalASRToRunningCaptureWithoutRestarting() async {
        let captureService = FakeAudioCaptureService()
        let asrService = FakeASRService()
        let model = AudioCaptureDiagnosticsModel(
            captureService: captureService,
            asrService: asrService
        )
        let chunk = makeAudioChunk(rms: 0.02, startHostTime: 20)

        await model.startCapture(
            audioSourceOption: .systemOutput,
            asrBackend: .mock
        )
        #expect(captureService.startRequests == [.systemOutput])

        await model.startCapture(
            audioSourceOption: .systemOutput,
            voiceActivitySettings: .defaults,
            asrBackend: .localParakeet,
            localASRSettings: LocalASRSettings(modelID: LocalASRSettings.parakeetV3ModelID),
            latencyProfile: .balanced,
            requiresASR: true
        )

        #expect(captureService.startRequests == [.systemOutput])
        #expect(captureService.state == .capturing)
        #expect(model.state.captureState == .capturing)
        #expect(asrService.isRunning)
        #expect(asrService.configuration.modelID == LocalASRSettings.parakeetV3ModelID)

        captureService.emitChunk(chunk)
        for _ in 0..<1_000 where asrService.acceptedAudioChunks.isEmpty {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(asrService.acceptedAudioChunks == [chunk])

        await model.stopASRRouting()

        #expect(captureService.state == .capturing)
        #expect(model.state.captureState == .capturing)
        #expect(asrService.stopCount == 1)
        #expect(model.state.asrDiagnostics.lifecycleState == .idle)

        await model.stopCapture()
    }

    @MainActor
    @Test
    func audioCaptureDiagnosticsCanRestartCaptureAndASRRouting() async {
        let captureService = FakeAudioCaptureService()
        let asrService = FakeASRService()
        let model = AudioCaptureDiagnosticsModel(
            captureService: captureService,
            asrService: asrService
        )
        let firstChunk = makeAudioChunk(rms: 0.02, startHostTime: 20)
        let secondChunk = makeAudioChunk(rms: 0.03, startHostTime: 1_020)

        await model.startCapture(
            audioSourceOption: .systemOutput,
            asrBackend: .localParakeet
        )
        captureService.emitChunk(firstChunk)

        for _ in 0..<1_000 where asrService.acceptedAudioChunks.isEmpty {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(captureService.startRequests == [.systemOutput])
        #expect(asrService.startCount == 1)
        #expect(asrService.acceptedAudioChunks == [firstChunk])

        await model.stopCapture()

        #expect(captureService.stopCount == 1)
        #expect(model.state.captureState == .idle)
        #expect(model.state.asrDiagnostics.lifecycleState == .idle)

        await model.startCapture(
            audioSourceOption: .systemOutput,
            asrBackend: .localParakeet
        )
        captureService.emitChunk(secondChunk)

        for _ in 0..<1_000 where asrService.acceptedAudioChunks.isEmpty {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(captureService.startRequests == [.systemOutput, .systemOutput])
        #expect(asrService.startCount == 2)
        #expect(model.state.captureState == .capturing)
        #expect(model.state.asrDiagnostics.lifecycleState == .ready)
        #expect(asrService.acceptedAudioChunks == [secondChunk])

        await model.stopCapture()
    }

    @MainActor
    @Test
    func audioCaptureDiagnosticsDoesNotRouteAudioChunksForMockASRBackend() async {
        let captureService = FakeAudioCaptureService()
        let asrService = FakeASRService()
        let model = AudioCaptureDiagnosticsModel(
            captureService: captureService,
            asrService: asrService
        )

        await model.startCapture(
            audioSourceOption: .systemOutput,
            asrBackend: .mock
        )

        captureService.emitChunk(makeAudioChunk(rms: 0.02))
        captureService.emitSpeechActivityEvent(.speechChunk(makeAudioChunk(rms: 0.02)))
        captureService.emitSpeechActivityEvent(
            .speechEnded(
                SpeechSegmentMetadata(
                    id: UUID(),
                    captureStartHostTime: 0,
                    captureEndHostTime: 1,
                    chunkCount: 1,
                    duration: 1,
                    peak: 0.02,
                    rms: 0.02
                )
            )
        )

        for _ in 0..<20 where model.state.voiceActivityDiagnostics.completedSegmentCount != 1 {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(!asrService.isRunning)
        #expect(asrService.acceptedAudioChunks.isEmpty)
        #expect(asrService.flushCount == 0)
        #expect(model.state.asrDiagnostics.backend == .mock)
        #expect(model.state.asrDiagnostics.acceptedSpeechChunkCount == 0)
    }

    @MainActor
    @Test
    func audioCaptureDiagnosticsRejectsSelectedAppForPhase4() async {
        let service = FakeAudioCaptureService()
        let model = AudioCaptureDiagnosticsModel(captureService: service)

        await model.startCapture(audioSourceOption: .selectedApp)

        #expect(service.startRequests.isEmpty)
        #expect(model.state.captureState == .error(AudioCaptureError.selectedAppCaptureUnavailable.localizedDescription))
        #expect(model.state.lastErrorMessage == AudioCaptureError.selectedAppCaptureUnavailable.localizedDescription)
    }

    @MainActor
    @Test
    func audioCaptureDiagnosticsSurfacesCaptureErrors() async {
        let service = FakeAudioCaptureService()
        service.startError = AudioCaptureError.sourceUnavailable
        let model = AudioCaptureDiagnosticsModel(captureService: service)

        await model.startCapture(audioSourceOption: .systemOutput)

        #expect(service.startRequests == [.systemOutput])
        #expect(model.state.captureState == .error(AudioCaptureError.sourceUnavailable.localizedDescription))
        #expect(model.state.lastErrorMessage == AudioCaptureError.sourceUnavailable.localizedDescription)
    }

    @MainActor
    @Test
    func liveSubtitleSessionValidatesRequiredPhase8Settings() async throws {
        let environment = try makeLiveSubtitleSessionForTesting()
        defer {
            environment.overlayController.hide()
            UserDefaults(suiteName: environment.suiteName)?.removePersistentDomain(forName: environment.suiteName)
        }

        environment.settingsStore.settings.audioSource = .selectedApp
        await environment.liveSession.start()

        #expect(environment.captureService.startRequests.isEmpty)
        #expect(environment.audioDiagnosticsModel.state.lastErrorMessage == "Live subtitles require System Output audio source for this phase.")

        environment.settingsStore.settings.audioSource = .systemOutput
        environment.settingsStore.settings.asrBackend = .mock
        await environment.liveSession.start()

        #expect(environment.captureService.startRequests.isEmpty)
        #expect(environment.audioDiagnosticsModel.state.lastErrorMessage == "Live subtitles require a local ASR backend (Parakeet or WhisperKit).")

        environment.settingsStore.settings.asrBackend = .localParakeet
        environment.settingsStore.settings.translationBackend = .remoteLAN
        await environment.liveSession.start()

        #expect(environment.captureService.startRequests.isEmpty)
        #expect(environment.audioDiagnosticsModel.state.lastErrorMessage == "Live subtitles do not support Remote LAN translation yet.")
    }

    @MainActor
    @Test
    func liveSubtitleSessionAcceptsAppleTranslationBackend() async throws {
        let environment = try makeLiveSubtitleSessionForTesting()
        defer {
            environment.overlayController.hide()
            UserDefaults(suiteName: environment.suiteName)?.removePersistentDomain(forName: environment.suiteName)
        }
        environment.settingsStore.settings.translationBackend = .appleTranslation

        await environment.liveSession.start()

        #expect(environment.liveSession.state == .running)
        #expect(environment.captureService.startRequests == [.systemOutput])
        #expect(environment.subtitleCoordinator.pipelineState == .listening)
    }

    @MainActor
    @Test
    func liveSubtitleSessionStartsCaptureShowsOverlayAndListensExternally() async throws {
        let environment = try makeLiveSubtitleSessionForTesting()
        defer {
            environment.overlayController.hide()
            UserDefaults(suiteName: environment.suiteName)?.removePersistentDomain(forName: environment.suiteName)
        }

        await environment.liveSession.start()

        #expect(environment.liveSession.state == .running)
        #expect(environment.overlayController.isVisible)
        #expect(environment.captureService.startRequests == [.systemOutput])
        #expect(environment.asrService.isRunning)
        #expect(environment.asrService.configuration.modelID == LocalASRSettings.parakeetV3ModelID)
        #expect(environment.subtitleCoordinator.pipelineState == .listening)
        #expect(environment.displayModel.overlayStatus == .listening)
        #expect(environment.displayModel.displayState == nil)
    }

    @MainActor
    @Test
    func liveSubtitleSessionCanStopAndStartAgain() async throws {
        let environment = try makeLiveSubtitleSessionForTesting()
        defer {
            environment.overlayController.hide()
            UserDefaults(suiteName: environment.suiteName)?.removePersistentDomain(forName: environment.suiteName)
        }
        let metadata = SpeechSegmentMetadata(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            captureStartHostTime: 20,
            captureEndHostTime: 1_020,
            chunkCount: 1,
            duration: 1,
            peak: 0.02,
            rms: 0.02
        )

        environment.asrService.finalEventOnFlush = .final(
            makeTranscriptSegment("Where are we going tonight?", stability: .final)
        )
        await environment.liveSession.start()
        environment.captureService.emitChunk(makeAudioChunk(rms: 0.02, startHostTime: 20))
        environment.captureService.emitSpeechActivityEvent(.speechEnded(metadata))

        for _ in 0..<1_000 where environment.displayModel.displayState?.primaryLine != "我们今晚要去哪里？" {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(environment.asrService.startCount == 1)
        #expect(environment.displayModel.displayState?.primaryLine == "我们今晚要去哪里？")

        await environment.liveSession.stop()

        #expect(environment.liveSession.state == .idle)
        #expect(environment.captureService.stopCount == 1)
        #expect(environment.asrService.stopCount == 1)
        #expect(environment.displayModel.displayState == nil)

        environment.asrService.finalEventOnFlush = .final(
            makeTranscriptSegment("I don't know", stability: .final)
        )
        await environment.liveSession.start()
        environment.captureService.emitChunk(makeAudioChunk(rms: 0.03, startHostTime: 1_020))
        environment.captureService.emitSpeechActivityEvent(.speechEnded(metadata))

        for _ in 0..<1_000 where environment.displayModel.displayState?.primaryLine != "我不知道。" {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(environment.liveSession.state == .running)
        #expect(environment.captureService.startRequests == [.systemOutput, .systemOutput])
        #expect(environment.asrService.startCount == 2)
        #expect(environment.displayModel.displayState?.primaryLine == "我不知道。")

        await environment.liveSession.stop()
    }

    @MainActor
    @Test
    func liveSubtitleSessionReusesExistingCaptureAndDetachesASROnStop() async throws {
        let environment = try makeLiveSubtitleSessionForTesting()
        defer {
            environment.overlayController.hide()
            UserDefaults(suiteName: environment.suiteName)?.removePersistentDomain(forName: environment.suiteName)
        }

        await environment.audioDiagnosticsModel.startCapture(
            audioSourceOption: .systemOutput,
            asrBackend: .mock
        )
        #expect(environment.captureService.startRequests == [.systemOutput])

        await environment.liveSession.start()

        #expect(environment.liveSession.state == .running)
        #expect(environment.captureService.startRequests == [.systemOutput])
        #expect(environment.captureService.state == .capturing)
        #expect(environment.asrService.isRunning)
        #expect(environment.subtitleCoordinator.pipelineState == .listening)

        await environment.liveSession.stop()

        #expect(environment.liveSession.state == .idle)
        #expect(environment.captureService.state == .capturing)
        #expect(environment.audioDiagnosticsModel.state.captureState == .capturing)
        #expect(environment.captureService.stopCount == 0)
        #expect(environment.asrService.stopCount == 1)
        #expect(environment.audioDiagnosticsModel.asrEventSink == nil)

        await environment.audioDiagnosticsModel.stopCapture()
    }

    @MainActor
    @Test
    func liveSubtitleSessionForwardsEventsWhenASRWasAlreadyRunning() async throws {
        let environment = try makeLiveSubtitleSessionForTesting()
        defer {
            environment.overlayController.hide()
            UserDefaults(suiteName: environment.suiteName)?.removePersistentDomain(forName: environment.suiteName)
        }
        let diagnosticsSegment = makeTranscriptSegment("Diagnostics only", stability: .final)
        let subtitleSegment = makeTranscriptSegment("Where are we going tonight?", stability: .final)

        await environment.audioDiagnosticsModel.startCapture(
            audioSourceOption: .systemOutput,
            voiceActivitySettings: .defaults,
            asrBackend: .localParakeet,
            localASRSettings: environment.settingsStore.settings.localASR,
            latencyProfile: .balanced
        )
        environment.asrService.emit(.final(diagnosticsSegment))

        for _ in 0..<1_000 where environment.audioDiagnosticsModel.state.asrDiagnostics.completedTranscriptCount != 1 {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(environment.audioDiagnosticsModel.state.asrDiagnostics.completedTranscriptCount == 1)
        #expect(environment.subtitleCoordinator.handledASREventCount == 0)

        await environment.liveSession.start()
        environment.asrService.emit(.final(subtitleSegment))

        for _ in 0..<1_000 where environment.displayModel.displayState?.primaryLine != "我们今晚要去哪里？" {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(environment.liveSession.state == .running)
        #expect(environment.captureService.startRequests == [.systemOutput])
        #expect(environment.asrService.isRunning)
        #expect(environment.subtitleCoordinator.handledASREventCount == 1)
        #expect(environment.displayModel.displayState?.primaryLine == "我们今晚要去哪里？")

        await environment.liveSession.stop()
        await environment.audioDiagnosticsModel.stopCapture()
    }

    @MainActor
    @Test
    func liveSubtitleSessionKeepsExistingCaptureWhenASRStartupFails() async throws {
        let environment = try makeLiveSubtitleSessionForTesting()
        defer {
            environment.overlayController.hide()
            UserDefaults(suiteName: environment.suiteName)?.removePersistentDomain(forName: environment.suiteName)
        }

        await environment.audioDiagnosticsModel.startCapture(
            audioSourceOption: .systemOutput,
            asrBackend: .mock
        )
        environment.asrService.startError = FakeASRServiceError.modelLoadFailed

        await environment.liveSession.start()

        #expect(environment.liveSession.state == .error("Fake ASR model load failed."))
        #expect(environment.captureService.state == .capturing)
        #expect(environment.audioDiagnosticsModel.state.captureState == .capturing)
        #expect(environment.captureService.startRequests == [.systemOutput])
        #expect(environment.captureService.stopCount == 0)
        #expect(environment.audioDiagnosticsModel.state.lastErrorMessage == "Fake ASR model load failed.")
        #expect(environment.subtitleCoordinator.pipelineState == .error)

        await environment.audioDiagnosticsModel.stopCapture()
    }

    @MainActor
    @Test
    func liveSubtitleSessionShowsPreparingStatusBeforeCaptureStarts() async throws {
        let environment = try makeLiveSubtitleSessionForTesting()
        defer {
            environment.overlayController.hide()
            UserDefaults(suiteName: environment.suiteName)?.removePersistentDomain(forName: environment.suiteName)
        }

        environment.captureService.onStart = {
            #expect(environment.overlayController.isVisible)
            #expect(environment.displayModel.overlayStatus == .preparingLiveSubtitles)
            #expect(environment.displayModel.displayState == nil)
        }

        await environment.liveSession.start()

        #expect(environment.liveSession.state == .running)
        #expect(environment.displayModel.overlayStatus == .listening)
    }

    @MainActor
    @Test
    func liveSubtitleSessionClearsListeningStatusAfterFirstAudioActivity() async throws {
        let environment = try makeLiveSubtitleSessionForTesting()
        defer {
            environment.overlayController.hide()
            UserDefaults(suiteName: environment.suiteName)?.removePersistentDomain(forName: environment.suiteName)
        }

        await environment.liveSession.start()
        #expect(environment.displayModel.overlayStatus == .listening)

        environment.captureService.emitLevel(
            AudioLevelSnapshot(
                rms: 0.05,
                peak: 0.12,
                timestamp: Date(timeIntervalSince1970: 5),
                sampleRate: 48_000,
                channelCount: 2
            )
        )

        for _ in 0..<40 where environment.displayModel.overlayStatus != nil {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(environment.displayModel.overlayStatus == nil)
        #expect(environment.displayModel.displayState == nil)

        await environment.liveSession.stop()
    }

    @MainActor
    @Test
    func liveSubtitleSessionShowsOverlayErrorWhenASRStartupFails() async throws {
        let environment = try makeLiveSubtitleSessionForTesting()
        defer {
            environment.overlayController.hide()
            UserDefaults(suiteName: environment.suiteName)?.removePersistentDomain(forName: environment.suiteName)
        }
        environment.asrService.startError = FakeASRServiceError.modelLoadFailed

        await environment.liveSession.start()

        #expect(environment.liveSession.state == .error("Fake ASR model load failed."))
        #expect(environment.overlayController.isVisible)
        #expect(environment.displayModel.overlayStatus == .error)
        #expect(environment.displayModel.displayState == nil)
        #expect(environment.captureService.startRequests.isEmpty)
        #expect(environment.audioDiagnosticsModel.state.lastErrorMessage == "Fake ASR model load failed.")
        #expect(environment.audioDiagnosticsModel.state.asrDiagnostics.lastErrorMessage == "Fake ASR model load failed.")
        #expect(environment.subtitleCoordinator.pipelineState == .error)
        #expect(environment.subtitleCoordinator.lastErrorMessage == "Fake ASR model load failed.")
    }

    @MainActor
    @Test
    func liveSubtitleSessionForwardsFinalASRToMockTranslatedOverlay() async throws {
        let environment = try makeLiveSubtitleSessionForTesting()
        defer {
            environment.overlayController.hide()
            UserDefaults(suiteName: environment.suiteName)?.removePersistentDomain(forName: environment.suiteName)
        }

        await environment.liveSession.start()
        #expect(environment.displayModel.overlayStatus == .listening)
        environment.asrService.emit(
            .final(makeTranscriptSegment("Hi", stability: .final))
        )

        for _ in 0..<40
            where environment.displayModel.displayState?.primaryLine != "[模拟翻译] Hi"
        {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(environment.displayModel.displayState?.primaryLine == "[模拟翻译] Hi")
        #expect(environment.displayModel.displayState?.isPartial == false)
        #expect(environment.displayModel.overlayStatus == nil)
        #expect(environment.translationService.requests.last?.segment.text == "Hi")
        #expect(environment.subtitleCoordinator.handledASREventCount == 1)
        #expect(environment.subtitleCoordinator.translationAttemptCount == 1)
        #expect(environment.subtitleCoordinator.translationSuccessCount == 1)
        #expect(environment.subtitleCoordinator.lastTranscriptText == "Hi")
        #expect(environment.subtitleCoordinator.lastTranslationText == "[模拟翻译] Hi")
    }

    @MainActor
    @Test
    func liveSubtitleSessionForwardsASRErrorsToDiagnosticsAndCoordinator() async throws {
        let environment = try makeLiveSubtitleSessionForTesting()
        defer {
            environment.overlayController.hide()
            UserDefaults(suiteName: environment.suiteName)?.removePersistentDomain(forName: environment.suiteName)
        }

        await environment.liveSession.start()
        environment.asrService.emit(.error("ASR failed"))

        for _ in 0..<40
            where environment.subtitleCoordinator.pipelineState != .error
        {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(environment.audioDiagnosticsModel.state.asrDiagnostics.lifecycleState == .error)
        #expect(environment.audioDiagnosticsModel.state.asrDiagnostics.lastErrorMessage == "ASR failed")
        #expect(environment.subtitleCoordinator.pipelineState == .error)
        #expect(environment.captureService.state == .capturing)
    }

    @MainActor
    @Test
    func liveSubtitleSessionStopClearsCaptureASRSinkAndSubtitleState() async throws {
        let environment = try makeLiveSubtitleSessionForTesting()
        defer {
            environment.overlayController.hide()
            UserDefaults(suiteName: environment.suiteName)?.removePersistentDomain(forName: environment.suiteName)
        }

        await environment.liveSession.start()
        environment.asrService.emit(
            .final(makeTranscriptSegment("Hi", stability: .final))
        )
        for _ in 0..<40 where environment.displayModel.displayState == nil {
            try? await Task.sleep(for: .milliseconds(1))
        }

        await environment.liveSession.stop()
        environment.asrService.emit(
            .final(makeTranscriptSegment("After stop", stability: .final))
        )
        try? await Task.sleep(for: .milliseconds(10))

        #expect(environment.liveSession.state == .idle)
        #expect(environment.captureService.stopCount == 1)
        #expect(environment.asrService.stopCount == 1)
        #expect(environment.subtitleCoordinator.pipelineState == .idle)
        #expect(environment.displayModel.displayState == nil)
        #expect(environment.displayModel.overlayStatus == nil)
        #expect(environment.audioDiagnosticsModel.asrEventSink == nil)
        #expect(environment.audioDiagnosticsModel.audioActivitySink == nil)
    }

    @Test
    func generatedInfoPlistDeclaresAudioCaptureUsageDescription() throws {
        let projectRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectFileURL = projectRootURL
            .appendingPathComponent("LiveSubtitleTranslator.xcodeproj")
            .appendingPathComponent("project.pbxproj")
        let projectFile = try String(contentsOf: projectFileURL, encoding: .utf8)
        let expectedBuildSetting = """
        INFOPLIST_KEY_NSAudioCaptureUsageDescription = "Live Subtitle Translator captures audio playing on this Mac to generate local translated subtitles.";
        """
        let usageDescriptionCount = projectFile.components(separatedBy: expectedBuildSetting).count - 1

        #expect(usageDescriptionCount == 2)
    }

    @Test
    func appTargetDeclaresRequiredSandboxEntitlements() throws {
        let projectRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectFileURL = projectRootURL
            .appendingPathComponent("LiveSubtitleTranslator.xcodeproj")
            .appendingPathComponent("project.pbxproj")
        let projectFile = try String(contentsOf: projectFileURL, encoding: .utf8)
        let expectedBuildSetting = "CODE_SIGN_ENTITLEMENTS = LiveSubtitleTranslator/LiveSubtitleTranslator.entitlements;"
        let entitlementsBuildSettingCount = projectFile.components(separatedBy: expectedBuildSetting).count - 1
        let outgoingNetworkBuildSettingCount = projectFile
            .components(separatedBy: "ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;")
            .count - 1

        #expect(entitlementsBuildSettingCount == 2)
        #expect(outgoingNetworkBuildSettingCount == 2)

        let entitlementsURL = projectRootURL
            .appendingPathComponent("LiveSubtitleTranslator")
            .appendingPathComponent("LiveSubtitleTranslator.entitlements")
        let entitlementsData = try Data(contentsOf: entitlementsURL)
        let plist = try PropertyListSerialization.propertyList(
            from: entitlementsData,
            options: [],
            format: nil
        )
        let entitlements = try #require(plist as? [String: Any])

        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(entitlements["com.apple.security.device.audio-input"] as? Bool == true)
        #expect(entitlements["com.apple.security.files.user-selected.read-only"] as? Bool == true)
        #expect(entitlements["com.apple.security.network.client"] as? Bool == true)
        let runtimeMachLookupNames = try #require(
            entitlements["com.apple.security.exception.mach-lookup.global-name"] as? [String]
        )
        #expect(runtimeMachLookupNames == ["com.apple.audioanalyticsd", "com.apple.dnssd.service"])
        let temporaryMachLookupNames = try #require(
            entitlements["com.apple.security.temporary-exception.mach-lookup.global-name"] as? [String]
        )
        #expect(temporaryMachLookupNames == ["com.apple.audioanalyticsd", "com.apple.dnssd.service"])
        let temporaryReadOnlyFilePaths = try #require(
            entitlements["com.apple.security.temporary-exception.files.absolute-path.read-only"] as? [String]
        )
        #expect(temporaryReadOnlyFilePaths == ["/Library/Preferences/com.apple.networkd.plist"])
    }

    @MainActor
    @Test
    func mockASRServiceEmitsScriptedEventsAndStopsIdempotently() async throws {
        let partialSegment = makeTranscriptSegment(
            "Where are we",
            stability: .partial
        )
        let finalSegment = makeTranscriptSegment(
            "Where are we going tonight?",
            stability: .final
        )
        let service = MockASRService(
            script: [
                MockASRScriptEvent(event: .partial(partialSegment), delay: .zero),
                MockASRScriptEvent(event: .final(finalSegment), delay: .zero)
            ]
        )
        var iterator = service.events.makeAsyncIterator()

        try await service.configure(
            ASRConfiguration(sourceLanguage: "en", latencyProfile: .fast)
        )
        try await service.start()
        try await service.start()

        let firstEvent = await iterator.next()
        let secondEvent = await iterator.next()

        #expect(firstEvent == .partial(partialSegment))
        #expect(secondEvent == .final(finalSegment))
        #expect(service.configuration.latencyProfile == .fast)

        await service.stop()
        await service.stop()

        #expect(!service.isRunning)
    }

    @MainActor
    @Test
    func mockTranslationServiceReturnsDeterministicChineseAndRecordsContext() async throws {
        let service = MockTranslationService()
        let contextSegment = makeTranscriptSegment(
            "Where are we going tonight?",
            stability: .final
        )
        let segment = makeTranscriptSegment(
            "I don't know, but we need to leave first.",
            stability: .final
        )

        let translation = try await service.translate(
            segment: segment,
            context: [contextSegment],
            targetLanguage: .simplifiedChinese
        )

        #expect(translation.transcriptID == segment.id)
        #expect(translation.translatedText == "我不知道，但先离开这里。")
        #expect(service.requests.count == 1)
        #expect(service.requests.first?.context == [contextSegment])
        #expect(service.requests.first?.targetLanguage == .simplifiedChinese)

        let fallbackSegment = makeTranscriptSegment(
            "Unmapped text",
            stability: .final
        )
        let fallbackTranslation = try await service.translate(
            segment: fallbackSegment,
            context: [],
            targetLanguage: .traditionalChinese
        )

        #expect(fallbackTranslation.translatedText == "[模擬翻譯] Unmapped text")
    }

    @MainActor
    @Test
    func appleTranslationServiceMapsSimplifiedChineseAndTranslatesInstalledPair() async throws {
        let client = FakeAppleTranslationClient()
        client.availabilityStatus = .installed
        client.translatedText = "你好"
        let service = AppleTranslationService(
            client: client,
            latencyProfileProvider: { .fast }
        )
        let segment = makeTranscriptSegment(" Hello ", stability: .final)

        let translation = try await service.translate(
            segment: segment,
            context: [],
            targetLanguage: .simplifiedChinese
        )

        #expect(translation.sourceText == "Hello")
        #expect(translation.translatedText == "你好")
        #expect(
            client.availabilityRequests == [
                FakeAppleTranslationClient.AvailabilityRequest(
                    source: "en",
                    target: "zh-Hans"
                )
            ]
        )
        #expect(client.translateRequests.first?.configuration.targetLanguageIdentifier == "zh-Hans")
        #expect(client.translateRequests.first?.configuration.strategy == .lowLatency)
        #expect(client.translateRequests.first?.shouldPrepare == false)
    }

    @MainActor
    @Test
    func appleTranslationServiceMapsTraditionalChineseAndPreparesSupportedPair() async throws {
        let client = FakeAppleTranslationClient()
        client.availabilityStatus = .supported
        client.translatedText = "你好"
        let service = AppleTranslationService(
            client: client,
            latencyProfileProvider: { .moreAccurate }
        )
        let segment = makeTranscriptSegment("Hello", stability: .final)

        _ = try await service.translate(
            segment: segment,
            context: [],
            targetLanguage: .traditionalChinese
        )

        #expect(client.translateRequests.first?.configuration.sourceLanguageIdentifier == "en")
        #expect(client.translateRequests.first?.configuration.targetLanguageIdentifier == "zh-Hant")
        #expect(client.translateRequests.first?.configuration.strategy == .highFidelity)
        #expect(client.translateRequests.first?.shouldPrepare == true)
    }

    @MainActor
    @Test
    func appleTranslationServiceUsesTranscriptSourceLanguage() async throws {
        let client = FakeAppleTranslationClient()
        client.availabilityStatus = .installed
        client.translatedText = "こんにちは"
        let service = AppleTranslationService(client: client)
        let segment = makeTranscriptSegment(
            "Bonjour",
            stability: .final,
            sourceLanguage: "fr"
        )

        _ = try await service.translate(
            segment: segment,
            context: [],
            targetLanguage: SubtitleLanguage("ja")
        )

        #expect(
            client.availabilityRequests == [
                FakeAppleTranslationClient.AvailabilityRequest(
                    source: "fr",
                    target: "ja"
                )
            ]
        )
        #expect(client.translateRequests.first?.configuration.sourceLanguageIdentifier == "fr")
        #expect(client.translateRequests.first?.configuration.targetLanguageIdentifier == "ja")
    }

    @MainActor
    @Test
    func appleTranslationServiceRejectsUnsupportedAndEmptyInput() async throws {
        let client = FakeAppleTranslationClient()
        client.availabilityStatus = .unsupported
        let service = AppleTranslationService(client: client)

        do {
            _ = try await service.translate(
                segment: makeTranscriptSegment("Hello", stability: .final),
                context: [],
                targetLanguage: .simplifiedChinese
            )
            Issue.record("Expected unsupported language pair error")
        } catch {
            #expect(error.localizedDescription == "Apple Translation does not support en to zh-Hans on this Mac.")
        }

        do {
            _ = try await service.translate(
                segment: makeTranscriptSegment("   ", stability: .final),
                context: [],
                targetLanguage: .simplifiedChinese
            )
            Issue.record("Expected empty translation error")
        } catch {
            #expect(error.localizedDescription == "There is no text to translate.")
        }

        #expect(client.translateRequests.isEmpty)
    }

    @MainActor
    @Test
    func appleTranslationServicePropagatesTranslationFailureWithoutFallback() async throws {
        let client = FakeAppleTranslationClient()
        client.translationError = TranslationServiceError.remoteLANUnavailable
        let service = AppleTranslationService(client: client)

        do {
            _ = try await service.translate(
                segment: makeTranscriptSegment("Hello", stability: .final),
                context: [],
                targetLanguage: .simplifiedChinese
            )
            Issue.record("Expected translation failure")
        } catch {
            #expect(error.localizedDescription == "Remote LAN translation is not implemented yet.")
        }

        #expect(client.translateRequests.count == 1)
    }

    @MainActor
    @Test
    func translationRouterChoosesConfiguredBackendAndRejectsRemoteLAN() async throws {
        let (settingsStore, suiteName) = try makeIsolatedSettingsStore()
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        let mockService = RecordingTranslationService(translatedText: "模拟")
        let appleService = RecordingTranslationService(translatedText: "苹果")
        let nllbService = RecordingTranslationService(translatedText: "本地")
        let hunyuanService = RecordingTranslationService(translatedText: "混元")
        let router = TranslationRouterService(
            settingsStore: settingsStore,
            mockTranslationService: mockService,
            appleTranslationService: appleService,
            nllbTranslationService: nllbService,
            hunyuanTranslationService: hunyuanService
        )
        let segment = makeTranscriptSegment("Hello", stability: .final)

        settingsStore.settings.translationBackend = .mock
        let mockTranslation = try await router.translate(
            segment: segment,
            context: [],
            targetLanguage: .simplifiedChinese
        )

        settingsStore.settings.translationBackend = .appleTranslation
        let appleTranslation = try await router.translate(
            segment: segment,
            context: [],
            targetLanguage: .simplifiedChinese
        )

        settingsStore.settings.translationBackend = .localNLLB
        let nllbTranslation = try await router.translate(
            segment: segment,
            context: [],
            targetLanguage: .simplifiedChinese
        )

        settingsStore.settings.translationBackend = .localHunyuanMT
        let hunyuanTranslation = try await router.translate(
            segment: segment,
            context: [],
            targetLanguage: .simplifiedChinese
        )

        settingsStore.settings.translationBackend = .remoteLAN
        do {
            _ = try await router.translate(
                segment: segment,
                context: [],
                targetLanguage: .simplifiedChinese
            )
            Issue.record("Expected remote LAN routing error")
        } catch {
            #expect(error.localizedDescription == "Remote LAN translation is not implemented yet.")
        }

        #expect(mockTranslation.translatedText == "模拟")
        #expect(appleTranslation.translatedText == "苹果")
        #expect(nllbTranslation.translatedText == "本地")
        #expect(hunyuanTranslation.translatedText == "混元")
        #expect(mockService.requests.count == 1)
        #expect(appleService.requests.count == 1)
        #expect(nllbService.requests.count == 1)
        #expect(hunyuanService.requests.count == 1)
    }

    /// End-to-end check that downloads the real NLLB CoreML model (~3.2 GB) and
    /// runs the decode loop. Gated behind an env var so the normal suite skips it.
    /// Run with: RUN_NLLB_INTEGRATION=1 ... -only-testing:.../nllbEngineTranslatesEnglishToChineseEndToEnd
    @Test
    func nllbEngineTranslatesEnglishToChineseEndToEnd() async throws {
        guard ProcessInfo.processInfo.environment["RUN_NLLB_INTEGRATION"] == "1" else { return }

        let engine = LiveNLLBEngine()
        let source = "Hello, how are you today?"
        let translated = try await engine.translate(
            text: source,
            sourceLanguage: .english,
            targetLanguage: .simplifiedChinese
        )

        print("NLLB_RESULT_SOURCE: \(source)")
        print("NLLB_RESULT_TRANSLATION: \(translated)")

        #expect(!translated.isEmpty)
        // Expect at least one CJK Han character in the output.
        let containsHan = translated.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        #expect(containsHan, "expected Chinese output, got: \(translated)")
    }

    /// End-to-end check that downloads the real Hunyuan-MT MLX model (~1.9 GB) and
    /// runs the decode loop on the GPU. Gated behind an env var; writes the result
    /// to Application Support for inspection.
    @Test
    func hunyuanEngineTranslatesEnglishToChineseEndToEnd() async throws {
        guard ProcessInfo.processInfo.environment["RUN_HUNYUAN_INTEGRATION"] == "1" else { return }

        let engine = LiveHunyuanEngine()
        let source = "This is a reference, not a tutorial."
        let translated = try await engine.translate(
            text: source,
            sourceLanguage: .english,
            targetLanguage: .simplifiedChinese
        )

        print("HUNYUAN_RESULT: \(source) => \(translated)")
        #expect(!translated.isEmpty)
        let containsHan = translated.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        #expect(containsHan, "expected Chinese output, got: \(translated)")
    }

    @Test
    func nllbTokenizationMapsLanguagesAndBuildsDecodingSequences() {
        // FLORES-200 language mapping.
        #expect(NLLBTokenization.floresCode(for: .english) == "eng_Latn")
        #expect(NLLBTokenization.floresCode(for: .simplifiedChinese) == "zho_Hans")
        #expect(NLLBTokenization.floresCode(for: .traditionalChinese) == "zho_Hant")
        #expect(NLLBTokenization.floresCode(for: SubtitleLanguage("ja")) == nil)

        // Encoder input: [srcLang, ...tokens..., EOS] padded with PAD; mask 1 then 0.
        let (inputIDs, attentionMask) = NLLBTokenization.encoderInput(
            sourceTokenIDs: [10, 20, 30],
            sourceLanguageID: 256_047,
            maxLength: 8
        )
        #expect(inputIDs == [256_047, 10, 20, 30, NLLBTokenization.eosTokenID, 1, 1, 1])
        #expect(attentionMask == [1, 1, 1, 1, 1, 0, 0, 0])

        // Overlong input keeps the language prefix and a trailing EOS.
        let (truncatedIDs, truncatedMask) = NLLBTokenization.encoderInput(
            sourceTokenIDs: [11, 12, 13, 14, 15, 16],
            sourceLanguageID: 256_047,
            maxLength: 4
        )
        #expect(truncatedIDs.count == 4)
        #expect(truncatedIDs.first == 256_047)
        #expect(truncatedIDs.last == NLLBTokenization.eosTokenID)
        #expect(truncatedMask == [1, 1, 1, 1])

        // Decoder seed: [</s>, <target lang code>].
        #expect(NLLBTokenization.decoderSeed(forcedBOSTokenID: 256_200) == [NLLBTokenization.eosTokenID, 256_200])

        // Argmax over a logits row.
        #expect(NLLBTokenization.argmax([0.1, 0.9, 0.3, -1.0]) == 1)
    }

    @MainActor
    @Test
    func parakeetASRServiceLoadsSelectedModelOnceAndFlushesTranscript() async throws {
        let transcriber = FakeParakeetTranscriber()
        let service = ParakeetASRService(transcriber: transcriber)
        var iterator = service.events.makeAsyncIterator()
        let configuration = ASRConfiguration(
            sourceLanguage: "en",
            latencyProfile: .fast,
            modelID: LocalASRSettings.parakeetV3ModelID
        )
        let firstChunk = makeAudioChunk(rms: 0.02, duration: 0.5)
        let secondChunk = makeAudioChunk(rms: 0.03, duration: 0.5)

        try await service.configure(configuration)
        try await service.start()
        try await service.start()
        try await service.acceptAudioChunk(firstChunk)
        try await service.acceptAudioChunk(secondChunk)
        try await service.flush()

        let event = await iterator.next()

        #expect(await transcriber.loadedModelIDs == [LocalASRSettings.parakeetV3ModelID])
        #expect(await transcriber.transcribedSamples.first?.count == firstChunk.samples.count + secondChunk.samples.count)
        #expect(service.pendingSampleCount == 0)
        if case let .final(segment) = event {
            #expect(segment.text == "Hello from Parakeet")
            #expect(segment.sourceLanguage == "en")
            #expect(segment.endTime == 1)
        } else {
            Issue.record("Expected final transcript")
        }
    }

    @MainActor
    @Test
    func whisperKitASRServiceLoadsSelectedWhisperModelAndFlushesTranscript() async throws {
        let transcriber = FakeWhisperKitTranscriber()
        let service = WhisperKitASRService(transcriber: transcriber)
        var iterator = service.events.makeAsyncIterator()
        try await service.configure(
            ASRConfiguration(
                sourceLanguage: "en",
                latencyProfile: .balanced,
                modelID: LocalASRSettings.whisperLargeV3ModelID
            )
        )
        try await service.start()
        try await service.acceptAudioChunk(makeAudioChunk(rms: 0.02, duration: 0.5))
        try await service.flush()

        let event = await iterator.next()
        #expect(await transcriber.loadedModelIDs == [LocalASRSettings.whisperLargeV3ModelID])
        #expect(await transcriber.transcribedLanguages == ["en"])
        if case let .final(segment) = event {
            #expect(segment.text == "Hello from WhisperKit")
        } else {
            Issue.record("Expected final transcript")
        }
    }

    @MainActor
    @Test
    func parakeetASRServiceIgnoresEmptyAndStoppedInput() async throws {
        let transcriber = FakeParakeetTranscriber()
        let service = ParakeetASRService(transcriber: transcriber)

        try await service.acceptAudioChunk(makeAudioChunk(rms: 0.02))
        try await service.flush()

        #expect(service.pendingSampleCount == 0)
        #expect(await transcriber.transcribedSamples.isEmpty)

        try await service.start()
        try await service.flush()

        #expect(await transcriber.transcribedSamples.isEmpty)

        try await service.acceptAudioChunk(makeAudioChunk(rms: 0.02))
        await service.stop()
        await service.stop()

        #expect(service.pendingSampleCount == 0)
        #expect(!service.isRunning)
    }

    @MainActor
    @Test
    func parakeetASRServiceEmitsErrorWhenTranscriptionFails() async throws {
        let transcriber = FakeParakeetTranscriber()
        await transcriber.setTranscriptionError(FakeParakeetTranscriberError.transcriptionFailed)
        let service = ParakeetASRService(transcriber: transcriber)
        var iterator = service.events.makeAsyncIterator()

        try await service.start()
        try await service.acceptAudioChunk(makeAudioChunk(rms: 0.02))

        do {
            try await service.flush()
            Issue.record("Expected flush to throw")
        } catch {
            #expect(error.localizedDescription == "Fake Parakeet transcription failed.")
        }

        let event = await iterator.next()
        #expect(event == .error("Fake Parakeet transcription failed."))
        #expect(service.pendingSampleCount == 0)
    }

    @MainActor
    @Test
    func mockSubtitleTickerCyclesThroughLines() {
        let displayModel = SubtitleDisplayModel()
        let ticker = MockSubtitleTicker(
            displayModel: displayModel,
            lines: ["第一句", "第二句"],
            interval: .seconds(60)
        )

        ticker.emitNext()
        #expect(displayModel.displayState?.primaryLine == "第一句")

        ticker.emitNext()
        #expect(displayModel.displayState?.primaryLine == "第二句")

        ticker.emitNext()
        #expect(displayModel.displayState?.primaryLine == "第一句")
    }

    @MainActor
    @Test
    func mockSubtitleTickerStartStopIsIdempotent() {
        let displayModel = SubtitleDisplayModel()
        let ticker = MockSubtitleTicker(
            displayModel: displayModel,
            lines: ["一句"],
            interval: .seconds(60)
        )

        ticker.start()
        ticker.start()

        #expect(ticker.isRunning)
        #expect(displayModel.displayState?.primaryLine == "一句")

        ticker.stop()
        ticker.stop()

        #expect(!ticker.isRunning)
        #expect(displayModel.displayState == nil)
    }

    @MainActor
    @Test
    func subtitleDisplayModelUpdatesAndClearsDisplayState() {
        let displayModel = SubtitleDisplayModel()
        let updatedAt = Date(timeIntervalSince1970: 100)
        let state = SubtitleDisplayState(
            primaryLine: "第一行",
            secondaryLine: "第二行",
            isPartial: true,
            updatedAt: updatedAt
        )

        displayModel.update(state)
        #expect(displayModel.displayState == state)
        #expect(displayModel.overlayStatus == nil)

        displayModel.clear()
        #expect(displayModel.displayState == nil)
        #expect(displayModel.overlayStatus == nil)
    }

    @MainActor
    @Test
    func subtitleDisplayModelTracksOverlayStatusSeparatelyFromSubtitles() {
        let displayModel = SubtitleDisplayModel()
        let state = SubtitleDisplayState(
            primaryLine: "字幕",
            secondaryLine: nil,
            isPartial: false
        )

        displayModel.showStatus(.preparingLiveSubtitles)
        #expect(displayModel.overlayStatus == .preparingLiveSubtitles)
        #expect(displayModel.overlayStatus?.displayText == "准备字幕…")
        #expect(displayModel.displayState == nil)

        displayModel.update(state)
        #expect(displayModel.displayState == state)
        #expect(displayModel.overlayStatus == nil)

        displayModel.showStatus(.listening)
        #expect(displayModel.displayState == state)
        #expect(displayModel.overlayStatus == nil)
        displayModel.clearStatus()
        #expect(displayModel.overlayStatus == nil)

        displayModel.clear()
        displayModel.showStatus(.error)
        #expect(displayModel.overlayStatus?.displayText == "字幕暂不可用")
        displayModel.clear()
        #expect(displayModel.displayState == nil)
        #expect(displayModel.overlayStatus == nil)
    }

    @MainActor
    @Test
    func subtitleLineWrapperHandlesBasicWrappingAndTruncation() {
        let wrapper = SubtitleLineWrapper(maxCharsPerLine: 5, maxLines: 2)

        #expect(wrapper.wrap("") == [])
        #expect(wrapper.wrap("这是测试") == ["这是测试"])
        #expect(wrapper.wrap("这是一个测试字幕") == ["这是一个测", "试字幕"])
        #expect(wrapper.wrap("等等，我来了。OK") == ["等等，我来", "了。OK"])

        let truncatingWrapper = SubtitleLineWrapper(maxCharsPerLine: 5, maxLines: 2)
        #expect(truncatingWrapper.wrap("一二三四五六七八九十一") == ["一二三四五", "六七..."])
    }

    @MainActor
    @Test
    func metricsRecorderStoresStageTimestampsBySegment() {
        let recorder = MetricsRecorder()
        let segmentID = UUID()
        let timestamp = Date(timeIntervalSince1970: 200)

        recorder.record(.translationStarted, segmentID: segmentID, at: timestamp)

        #expect(
            recorder.events(for: segmentID) == [
                MetricsEvent(
                    segmentID: segmentID,
                    stage: .translationStarted,
                    timestamp: timestamp
                )
            ]
        )

        recorder.reset()
        #expect(recorder.events.isEmpty)
    }

    @MainActor
    @Test
    func subtitleCoordinatorFinalSegmentUpdatesOverlayWithTranslation() async throws {
        let (coordinator, displayModel, translationService, metricsRecorder, suiteName) = try makeCoordinatorForTesting()
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        let segment = makeTranscriptSegment(
            "Where are we going tonight?",
            stability: .final
        )

        await coordinator.handleASREvent(.final(segment))

        #expect(displayModel.displayState?.primaryLine == "我们今晚要去哪里？")
        #expect(displayModel.displayState?.secondaryLine == nil)
        #expect(displayModel.displayState?.isPartial == false)
        #expect(translationService.requests.count == 1)
        #expect(metricsRecorder.events(for: segment.id).map(\.stage) == [
            .asrFinalReceived,
            .translationStarted,
            .translationFinished,
            .overlayRendered
        ])
    }

    @MainActor
    @Test
    func subtitleCoordinatorIgnoresUnstablePartial() async throws {
        let (coordinator, displayModel, translationService, metricsRecorder, suiteName) = try makeCoordinatorForTesting()
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        let segment = makeTranscriptSegment("Where are we", stability: .partial)

        await coordinator.handleASREvent(.partial(segment))

        #expect(displayModel.displayState == nil)
        #expect(translationService.requests.isEmpty)
        #expect(metricsRecorder.events(for: segment.id).map(\.stage) == [.asrPartialReceived])
    }

    @MainActor
    @Test
    func subtitleCoordinatorStablePartialUpdatesOverlayAsPartial() async throws {
        let (coordinator, displayModel, _, _, suiteName) = try makeCoordinatorForTesting()
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        let segment = makeTranscriptSegment("I don't know", stability: .stablePartial)

        await coordinator.handleASREvent(.partial(segment))

        #expect(displayModel.displayState?.primaryLine == "我不知道。")
        #expect(displayModel.displayState?.isPartial == true)
    }

    @MainActor
    @Test
    func subtitleCoordinatorFinalCanReplaceMatchingStablePartial() async throws {
        let (coordinator, displayModel, _, _, suiteName) = try makeCoordinatorForTesting()
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        let partialSegment = makeTranscriptSegment("I don't know", stability: .stablePartial)
        let finalSegment = makeTranscriptSegment("I don't know", stability: .final)

        await coordinator.handleASREvent(.partial(partialSegment))
        #expect(displayModel.displayState?.isPartial == true)

        await coordinator.handleASREvent(.final(finalSegment))

        #expect(displayModel.displayState?.primaryLine == "我不知道。")
        #expect(displayModel.displayState?.isPartial == false)
    }

    @MainActor
    @Test
    func subtitleCoordinatorSuppressesDuplicateFinalDisplay() async throws {
        let (coordinator, displayModel, _, _, suiteName) = try makeCoordinatorForTesting()
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        let firstSegment = makeTranscriptSegment(
            "This is not a good idea.",
            stability: .final
        )
        let duplicateSegment = makeTranscriptSegment(
            "This is not a good idea.",
            stability: .final
        )

        await coordinator.handleASREvent(.final(firstSegment))
        let firstDisplayState = displayModel.displayState

        await coordinator.handleASREvent(.final(duplicateSegment))

        #expect(displayModel.displayState == firstDisplayState)
    }

    @MainActor
    @Test
    func subtitleCoordinatorSurfacesTranslationErrorsWithoutFallbackAndClearsOnSuccess() async throws {
        let (settingsStore, suiteName) = try makeIsolatedSettingsStore()
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        let displayModel = SubtitleDisplayModel()
        let translationService = RecordingTranslationService(
            translatedText: "成功",
            error: TranslationServiceError.remoteLANUnavailable
        )
        let coordinator = SubtitleCoordinator(
            settingsStore: settingsStore,
            displayModel: displayModel,
            asrService: MockASRService(script: []),
            translationService: translationService,
            metricsRecorder: MetricsRecorder()
        )
        displayModel.update(SubtitleDisplayState(primaryLine: "旧字幕"))

        await coordinator.handleASREvent(
            .final(makeTranscriptSegment("Hello", stability: .final))
        )

        #expect(coordinator.pipelineState == .error)
        #expect(coordinator.lastErrorMessage == "Remote LAN translation is not implemented yet.")
        #expect(displayModel.displayState?.primaryLine == "旧字幕")
        #expect(coordinator.handledASREventCount == 1)
        #expect(coordinator.translationAttemptCount == 1)
        #expect(coordinator.translationSuccessCount == 0)
        #expect(coordinator.lastTranscriptText == "Hello")
        #expect(coordinator.lastTranslationText == nil)

        translationService.error = nil
        await coordinator.handleASREvent(
            .final(makeTranscriptSegment("Recovered", stability: .final))
        )

        #expect(coordinator.lastErrorMessage == nil)
        #expect(displayModel.displayState?.primaryLine == "成功")
        #expect(coordinator.handledASREventCount == 2)
        #expect(coordinator.translationAttemptCount == 2)
        #expect(coordinator.translationSuccessCount == 1)
        #expect(coordinator.lastTranscriptText == "Recovered")
        #expect(coordinator.lastTranslationText == "成功")
    }

    @MainActor
    @Test
    func subtitleCoordinatorDoesNotRestoreListeningStatusAfterAudioActivity() async throws {
        let (coordinator, displayModel, _, _, suiteName) = try makeCoordinatorForTesting(
            subtitleHoldDuration: .milliseconds(10)
        )
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        await coordinator.startExternalEvents(status: .listening)
        coordinator.noteExternalAudioActivity()
        await coordinator.handleASREvent(.final(makeTranscriptSegment("Hello", stability: .final)))

        for _ in 0..<40 where displayModel.displayState == nil {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(displayModel.overlayStatus == nil)
        #expect(displayModel.displayState != nil)

        for _ in 0..<80 where displayModel.displayState != nil {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(displayModel.displayState == nil)
        #expect(displayModel.overlayStatus == nil)
    }

    @MainActor
    @Test
    func subtitleCoordinatorShowsOverlayErrorWhenTranslationFailsBeforeFirstSubtitle() async throws {
        let (settingsStore, suiteName) = try makeIsolatedSettingsStore()
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        let displayModel = SubtitleDisplayModel()
        let translationService = RecordingTranslationService(
            translatedText: "不会显示",
            error: TranslationServiceError.remoteLANUnavailable
        )
        let coordinator = SubtitleCoordinator(
            settingsStore: settingsStore,
            displayModel: displayModel,
            asrService: MockASRService(script: []),
            translationService: translationService,
            metricsRecorder: MetricsRecorder()
        )

        await coordinator.startExternalEvents(status: .listening)
        await coordinator.handleASREvent(
            .final(makeTranscriptSegment("Hello", stability: .final))
        )

        #expect(coordinator.pipelineState == .error)
        #expect(coordinator.lastErrorMessage == "Remote LAN translation is not implemented yet.")
        #expect(displayModel.displayState == nil)
        #expect(displayModel.overlayStatus == .error)
        #expect(coordinator.handledASREventCount == 1)
        #expect(coordinator.translationAttemptCount == 1)
        #expect(coordinator.translationSuccessCount == 0)
    }

    @MainActor
    @Test
    func subtitleCoordinatorStopCancelsWorkAndClearsDisplay() async throws {
        let (coordinator, displayModel, _, _, suiteName) = try makeCoordinatorForTesting()
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        displayModel.update(SubtitleDisplayState(primaryLine: "测试"))
        await coordinator.start()

        #expect(coordinator.pipelineState.isRunning)

        await coordinator.stop()

        #expect(coordinator.pipelineState == .idle)
        #expect(displayModel.displayState == nil)
    }

    @MainActor
    @Test
    func subtitleCoordinatorHoldClearsOnlyCurrentSubtitle() async throws {
        let (coordinator, displayModel, _, _, suiteName) = try makeCoordinatorForTesting(
            subtitleHoldDuration: .milliseconds(200)
        )
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        let firstSegment = makeTranscriptSegment(
            "Where are we going tonight?",
            stability: .final
        )
        let secondSegment = makeTranscriptSegment(
            "Wait, I hear someone coming.",
            stability: .final
        )

        await coordinator.handleASREvent(.final(firstSegment))
        try await Task.sleep(for: .milliseconds(50))
        await coordinator.handleASREvent(.final(secondSegment))
        try await Task.sleep(for: .milliseconds(170))

        #expect(displayModel.displayState?.primaryLine == "等等，我听到有人来了。")

        try await Task.sleep(for: .milliseconds(80))
        #expect(displayModel.displayState == nil)
    }

    @MainActor
    @Test
    func overlayControllerShowHideTracksVisibilityAndSanitizesPersistedFrame() throws {
        let (settingsStore, suiteName) = try makeIsolatedSettingsStore()
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        settingsStore.settings.overlay.frame = OverlayFrame(
            x: -100_000,
            y: -100_000,
            width: 10,
            height: 10
        )

        let controller = SubtitleOverlayWindowController(
            settingsStore: settingsStore,
            displayModel: SubtitleDisplayModel()
        )

        controller.show()

        #expect(controller.isVisible)
        #expect(settingsStore.settings.overlay.frame.width >= 360)
        #expect(settingsStore.settings.overlay.frame.height >= 96)
        #expect(settingsStore.settings.overlay.frame.x > -100_000)
        #expect(settingsStore.settings.overlay.frame.y > -100_000)

        controller.hide()
        #expect(!controller.isVisible)
    }

    @MainActor
    @Test
    func overlayControllerLockAndResetPersistSettings() throws {
        let (settingsStore, suiteName) = try makeIsolatedSettingsStore()
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        let controller = SubtitleOverlayWindowController(
            settingsStore: settingsStore,
            displayModel: SubtitleDisplayModel()
        )

        controller.setLocked(false)
        #expect(!settingsStore.settings.overlay.isLocked)

        controller.toggleLocked()
        #expect(settingsStore.settings.overlay.isLocked)

        settingsStore.settings.overlay.frame = OverlayFrame(
            x: -100_000,
            y: -100_000,
            width: 10,
            height: 10
        )

        controller.resetFrame()

        #expect(settingsStore.settings.overlay.frame.width >= 360)
        #expect(settingsStore.settings.overlay.frame.height >= 96)
        #expect(settingsStore.settings.overlay.frame.x > -100_000)
        #expect(settingsStore.settings.overlay.frame.y > -100_000)
    }

    private struct LiveSubtitleSessionTestEnvironment {
        let liveSession: LiveSubtitleSessionController
        let settingsStore: SettingsStore
        let overlayController: SubtitleOverlayWindowController
        let audioDiagnosticsModel: AudioCaptureDiagnosticsModel
        let subtitleCoordinator: SubtitleCoordinator
        let displayModel: SubtitleDisplayModel
        let translationService: MockTranslationService
        let captureService: FakeAudioCaptureService
        let asrService: FakeASRService
        let suiteName: String
    }

    @MainActor
    private func makeLiveSubtitleSessionForTesting() throws -> LiveSubtitleSessionTestEnvironment {
        let (settingsStore, suiteName) = try makeIsolatedSettingsStore()
        settingsStore.settings.audioSource = .systemOutput
        settingsStore.settings.asrBackend = .localParakeet
        settingsStore.settings.translationBackend = .mock
        settingsStore.settings.localASR = LocalASRSettings(modelID: LocalASRSettings.parakeetV3ModelID)

        let displayModel = SubtitleDisplayModel()
        let overlayController = SubtitleOverlayWindowController(
            settingsStore: settingsStore,
            displayModel: displayModel
        )
        let captureService = FakeAudioCaptureService()
        let asrService = FakeASRService()
        let audioDiagnosticsModel = AudioCaptureDiagnosticsModel(
            captureService: captureService,
            asrService: asrService
        )
        let translationService = MockTranslationService()
        let subtitleCoordinator = SubtitleCoordinator(
            settingsStore: settingsStore,
            displayModel: displayModel,
            asrService: MockASRService(script: []),
            translationService: translationService,
            metricsRecorder: MetricsRecorder(),
            subtitleHoldDuration: .seconds(60)
        )
        let liveSession = LiveSubtitleSessionController(
            settingsStore: settingsStore,
            overlayController: overlayController,
            audioDiagnosticsModel: audioDiagnosticsModel,
            subtitleCoordinator: subtitleCoordinator
        )

        return LiveSubtitleSessionTestEnvironment(
            liveSession: liveSession,
            settingsStore: settingsStore,
            overlayController: overlayController,
            audioDiagnosticsModel: audioDiagnosticsModel,
            subtitleCoordinator: subtitleCoordinator,
            displayModel: displayModel,
            translationService: translationService,
            captureService: captureService,
            asrService: asrService,
            suiteName: suiteName
        )
    }

    @MainActor
    private func makeCoordinatorForTesting(
        subtitleHoldDuration: Duration = .seconds(60)
    ) throws -> (
        SubtitleCoordinator,
        SubtitleDisplayModel,
        MockTranslationService,
        MetricsRecorder,
        String
    ) {
        let (settingsStore, suiteName) = try makeIsolatedSettingsStore()
        let displayModel = SubtitleDisplayModel()
        let translationService = MockTranslationService()
        let metricsRecorder = MetricsRecorder()
        let coordinator = SubtitleCoordinator(
            settingsStore: settingsStore,
            displayModel: displayModel,
            asrService: MockASRService(script: []),
            translationService: translationService,
            metricsRecorder: metricsRecorder,
            subtitleHoldDuration: subtitleHoldDuration
        )

        return (
            coordinator,
            displayModel,
            translationService,
            metricsRecorder,
            suiteName
        )
    }
}
