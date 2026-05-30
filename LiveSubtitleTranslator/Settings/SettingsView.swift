//
//  SettingsView.swift
//  LiveSubtitleTranslator
//
//  Created by Christian Merrill on 5/20/26.
//

import SwiftUI

private enum SettingsLayout {
    static let windowWidth: CGFloat = 820
    static let windowHeight: CGFloat = 760
    static let actionSpacing: CGFloat = 12
    static let audioButtonWidth: CGFloat = 220
}

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var subtitleCoordinator: SubtitleCoordinator
    @ObservedObject var overlayController: SubtitleOverlayWindowController
    @ObservedObject var audioDiagnosticsModel: AudioCaptureDiagnosticsModel
    @ObservedObject var liveSubtitleSessionController: LiveSubtitleSessionController
    @ObservedObject var translationLanguageCatalog: AppleTranslationLanguageCatalog
    @ObservedObject var whisperKitModelCatalog: WhisperKitModelCatalog
    @Environment(\.openURL) private var openURL

    private let audioPermissionSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )

    var body: some View {
        Form {
            Section("Pipeline") {
                LabeledContent("State", value: subtitleCoordinator.pipelineState.displayName)
                LabeledContent("Live Subtitles", value: liveSubtitleSessionController.state.displayName)
                LabeledContent("Translation Backend", value: settingsStore.settings.translationBackend.displayName)
                LabeledContent("Source Language", value: settingsStore.settings.sourceLanguage.displayName)
                LabeledContent("Target Language", value: settingsStore.settings.targetLanguage.displayName)
                LabeledContent("Subtitle ASR Events", value: "\(subtitleCoordinator.handledASREventCount)")
                LabeledContent("Translation Attempts", value: "\(subtitleCoordinator.translationAttemptCount)")
                LabeledContent("Translation Successes", value: "\(subtitleCoordinator.translationSuccessCount)")

                if let lastTranscriptText = subtitleCoordinator.lastTranscriptText {
                    LabeledContent("Subtitle Transcript", value: lastTranscriptText)
                }

                if let lastTranslationText = subtitleCoordinator.lastTranslationText {
                    LabeledContent("Subtitle Translation", value: lastTranslationText)
                }

                liveSubtitleActions

                if let lastErrorMessage = subtitleCoordinator.lastErrorMessage {
                    LabeledContent("Pipeline Error", value: lastErrorMessage)
                }
            }

            Section("Overlay") {
                LabeledContent("Visibility", value: overlayController.isVisible ? "Visible" : "Hidden")
                LabeledContent("Interaction", value: settingsStore.settings.overlay.isLocked ? "Locked" : "Unlocked")

                overlayActions
            }

            Section("Audio") {
                Picker("Audio Source", selection: $settingsStore.settings.audioSource) {
                    ForEach(AudioSourceOption.allCases) { source in
                        Text(source.displayName).tag(source)
                    }
                }

                Text("Starting capture may show macOS system audio recording permission. If access is denied, enable the app in Privacy & Security > Screen & System Audio Recording > System Audio Recording Only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                audioActions

                LabeledContent("Permission", value: audioDiagnosticsModel.state.permissionStatus.displayName)
                LabeledContent("Capture State", value: audioDiagnosticsModel.state.captureState.displayName)
                LabeledContent("Source Availability", value: audioDiagnosticsModel.state.sourceAvailability.displayName)
                LabeledContent("Sources Found", value: audioDiagnosticsModel.state.sourceCountDisplayValue)
                LabeledContent("RMS", value: audioDiagnosticsModel.state.lastLevel.rmsDisplayValue)
                LabeledContent("Peak", value: audioDiagnosticsModel.state.lastLevel.peakDisplayValue)
                LabeledContent("Chunks", value: audioDiagnosticsModel.state.preprocessingDiagnostics.emittedChunkCountDisplayValue)
                LabeledContent("Last Chunk", value: audioDiagnosticsModel.state.preprocessingDiagnostics.lastChunkDurationDisplayValue)
                LabeledContent("Queue Depth", value: audioDiagnosticsModel.state.preprocessingDiagnostics.queueDepthDisplayValue)
                LabeledContent("Dropped Frames", value: audioDiagnosticsModel.state.preprocessingDiagnostics.droppedFramesDisplayValue)
                LabeledContent("Audio Callbacks", value: audioDiagnosticsModel.state.preprocessingDiagnostics.callbackCountDisplayValue)
                LabeledContent("Captured Frames", value: audioDiagnosticsModel.state.preprocessingDiagnostics.capturedFrameCountDisplayValue)
                LabeledContent("VAD", value: audioDiagnosticsModel.state.voiceActivityDiagnostics.activityStateDisplayValue)
                LabeledContent("Speech Chunks", value: audioDiagnosticsModel.state.voiceActivityDiagnostics.emittedSpeechChunkCountDisplayValue)
                LabeledContent("Speech Segments", value: audioDiagnosticsModel.state.voiceActivityDiagnostics.completedSegmentCountDisplayValue)
                LabeledContent("Last Speech", value: audioDiagnosticsModel.state.voiceActivityDiagnostics.lastSpeechDurationDisplayValue)
                LabeledContent("Current Silence", value: audioDiagnosticsModel.state.voiceActivityDiagnostics.currentSilenceDurationDisplayValue)
                LabeledContent("VAD RMS", value: audioDiagnosticsModel.state.voiceActivityDiagnostics.lastChunkRMSDisplayValue)
                LabeledContent("VAD Peak", value: audioDiagnosticsModel.state.voiceActivityDiagnostics.lastChunkPeakDisplayValue)
                LabeledContent("ASR State", value: audioDiagnosticsModel.state.asrDiagnostics.lifecycleStateDisplayValue)
                LabeledContent("ASR Backend", value: audioDiagnosticsModel.state.asrDiagnostics.backendDisplayValue)
                LabeledContent("ASR Model", value: audioDiagnosticsModel.state.asrDiagnostics.modelID)
                LabeledContent("ASR Audio Chunks", value: audioDiagnosticsModel.state.asrDiagnostics.acceptedSpeechChunkCountDisplayValue)
                LabeledContent("ASR Transcripts", value: audioDiagnosticsModel.state.asrDiagnostics.completedTranscriptCountDisplayValue)
                LabeledContent("Last ASR Transcript", value: audioDiagnosticsModel.state.asrDiagnostics.lastTranscriptDisplayValue)

                if let captureWarningMessage = audioDiagnosticsModel.state.captureWarningMessage {
                    LabeledContent("Capture Warning", value: captureWarningMessage)
                }

                if let asrErrorMessage = audioDiagnosticsModel.state.asrDiagnostics.lastErrorMessage {
                    LabeledContent("ASR Error", value: asrErrorMessage)
                }

                if let lastErrorMessage = audioDiagnosticsModel.state.lastErrorMessage {
                    LabeledContent("Last Error", value: lastErrorMessage)
                }
            }

            Section("Backends") {
                Picker("ASR Backend", selection: $settingsStore.settings.asrBackend) {
                    ForEach(ASRBackend.userSelectableCases) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }

                if settingsStore.settings.asrBackend == .localWhisperKit {
                    Picker("WhisperKit Model", selection: $settingsStore.settings.localASR.modelID) {
                        ForEach(whisperKitModelCatalog.modelIDs, id: \.self) { modelID in
                            Text(LocalASRSettings.displayName(for: modelID)).tag(modelID)
                        }
                    }

                    if whisperKitModelCatalog.isRefreshing {
                        LabeledContent("WhisperKit Models", value: "Refreshing...")
                    }
                }

                Picker("Translation Backend", selection: $settingsStore.settings.translationBackend) {
                    ForEach(TranslationBackend.userSelectableCases) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }

                TextField("Remote Server URL", text: remoteServerURLText)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Subtitles") {
                Picker("Source Language", selection: $settingsStore.settings.sourceLanguage) {
                    ForEach(sourceLanguageOptions) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .disabled(areLiveAudioSettingsLocked)

                Picker("Target Language", selection: $settingsStore.settings.targetLanguage) {
                    ForEach(targetLanguageOptions) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                if translationLanguageCatalog.isLoading {
                    LabeledContent("Language Availability", value: "Refreshing...")
                } else if let statusMessage = translationLanguageCatalog.statusMessage {
                    LabeledContent("Language Availability", value: statusMessage)
                }

                Picker("Translation Profile", selection: $settingsStore.settings.latencyProfile) {
                    ForEach(LatencyProfile.allCases) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
                .disabled(areLiveAudioSettingsLocked)

                Picker("VAD Sensitivity", selection: $settingsStore.settings.voiceActivity.sensitivity) {
                    ForEach(VADSensitivity.allCases) { sensitivity in
                        Text(sensitivity.displayName).tag(sensitivity)
                    }
                }
                .disabled(areLiveAudioSettingsLocked)

                Stepper(
                    value: $settingsStore.settings.voiceActivity.finalSilenceDuration,
                    in: 0.2...3.0,
                    step: 0.1
                ) {
                    LabeledContent(
                        "Final Silence",
                        value: settingsStore.settings.voiceActivity.finalSilenceDurationDisplayValue
                    )
                }
                .disabled(areLiveAudioSettingsLocked)

                Text("Translation profile and VAD diagnostics apply cleanly when capture starts. Stop live subtitles or capture before changing them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Diagnostics") {
                Toggle("Diagnostics Enabled", isOn: $settingsStore.settings.diagnosticsEnabled)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(
            minWidth: SettingsLayout.windowWidth,
            idealWidth: SettingsLayout.windowWidth,
            minHeight: SettingsLayout.windowHeight,
            idealHeight: SettingsLayout.windowHeight
        )
        .task {
            await audioDiagnosticsModel.refreshSources()
            await refreshLanguageCatalog()
            await whisperKitModelCatalog.refresh(
                selectedModelID: settingsStore.settings.localASR.modelID
            )
        }
        .onChange(of: settingsStore.settings.sourceLanguage) {
            Task {
                await refreshLanguageCatalog()
            }
        }
        .onChange(of: settingsStore.settings.localASR.modelID) {
            Task {
                await whisperKitModelCatalog.refresh(
                    selectedModelID: settingsStore.settings.localASR.modelID
                )
            }
        }
    }

    private var areLiveAudioSettingsLocked: Bool {
        audioDiagnosticsModel.state.captureState.isRunning || liveSubtitleSessionController.state.isActive
    }

    private var sourceLanguageOptions: [SubtitleLanguage] {
        AppleTranslationLanguageCatalog.visibleLanguages(
            translationLanguageCatalog.sourceLanguages,
            including: settingsStore.settings.sourceLanguage,
            priority: [.english]
        )
    }

    private var targetLanguageOptions: [SubtitleLanguage] {
        AppleTranslationLanguageCatalog.visibleLanguages(
            translationLanguageCatalog.targetLanguages,
            including: settingsStore.settings.targetLanguage,
            priority: [.simplifiedChinese, .traditionalChinese, .english]
        )
    }

    private var liveSubtitleActions: some View {
        HStack(spacing: SettingsLayout.actionSpacing) {
            Button("Start Live Subtitles", systemImage: "dot.radiowaves.left.and.right") {
                Task {
                    await liveSubtitleSessionController.start()
                }
            }
            .disabled(liveSubtitleSessionController.state.isActive)

            Button("Stop Live Subtitles", systemImage: "stop.fill") {
                Task {
                    await liveSubtitleSessionController.stop()
                }
            }
            .disabled(!liveSubtitleSessionController.state.isActive)
        }
    }

    private var overlayActions: some View {
        HStack(spacing: SettingsLayout.actionSpacing) {
            Button(overlayController.isVisible ? "Hide Overlay" : "Show Overlay", systemImage: "captions.bubble") {
                overlayController.toggleVisibility()
            }

            Button(settingsStore.settings.overlay.isLocked ? "Unlock Overlay" : "Lock Overlay", systemImage: settingsStore.settings.overlay.isLocked ? "lock.open" : "lock") {
                overlayController.toggleLocked()
            }

            Button("Reset Position", systemImage: "arrow.counterclockwise") {
                overlayController.resetFrame()
            }
        }
    }

    private var audioActions: some View {
        Grid(alignment: .leading, horizontalSpacing: SettingsLayout.actionSpacing, verticalSpacing: 10) {
            GridRow {
                startCaptureButton
                stopCaptureButton
            }

            GridRow {
                refreshSourcesButton
                openPrivacySettingsButton
            }
        }
        .controlSize(.large)
    }

    private var startCaptureButton: some View {
        Button("Start Capture", systemImage: "waveform") {
            Task {
                await audioDiagnosticsModel.startCapture(
                    audioSourceOption: settingsStore.settings.audioSource,
                    voiceActivitySettings: settingsStore.settings.voiceActivity,
                    asrBackend: settingsStore.settings.asrBackend,
                    localASRSettings: settingsStore.settings.localASR,
                    sourceLanguage: settingsStore.settings.sourceLanguage,
                    latencyProfile: settingsStore.settings.latencyProfile
                )
            }
        }
        .disabled(audioDiagnosticsModel.state.captureState.isRunning || liveSubtitleSessionController.state.isActive)
        .frame(minWidth: SettingsLayout.audioButtonWidth)
    }

    private var stopCaptureButton: some View {
        Button("Stop Capture", systemImage: "stop.fill") {
            Task {
                await audioDiagnosticsModel.stopCapture()
            }
        }
        .disabled(!audioDiagnosticsModel.state.captureState.isRunning || liveSubtitleSessionController.state.isActive)
        .frame(minWidth: SettingsLayout.audioButtonWidth)
    }

    private var refreshSourcesButton: some View {
        Button("Refresh Sources", systemImage: "arrow.clockwise") {
            Task {
                await audioDiagnosticsModel.refreshSources()
            }
        }
        .frame(minWidth: SettingsLayout.audioButtonWidth)
    }

    private var openPrivacySettingsButton: some View {
        Button("Open Privacy Settings", systemImage: "gearshape") {
            if let audioPermissionSettingsURL {
                openURL(audioPermissionSettingsURL)
            }
        }
        .frame(minWidth: SettingsLayout.audioButtonWidth)
    }

    private var remoteServerURLText: Binding<String> {
        Binding {
            settingsStore.settings.remoteServerURL?.absoluteString ?? ""
        } set: { newValue in
            let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            settingsStore.settings.remoteServerURL = trimmedValue.isEmpty ? nil : URL(string: trimmedValue)
        }
    }

    private func refreshLanguageCatalog() async {
        let targetLanguage = await translationLanguageCatalog.refresh(
            sourceLanguage: settingsStore.settings.sourceLanguage,
            selectedTargetLanguage: settingsStore.settings.targetLanguage
        )

        if settingsStore.settings.targetLanguage != targetLanguage {
            settingsStore.settings.targetLanguage = targetLanguage
        }
    }
}
