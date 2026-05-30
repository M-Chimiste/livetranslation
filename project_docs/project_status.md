# Project Status

Prepared: 2026-05-21

## Current Status

Phase 0, Phase 1, Phase 2, Phase 3, Phase 4, Phase 5 / Task 009, Phase 6 / Task 010, Phase 7 / Task 011, Phase 8 / Task 012, and Phase 9 / Task 013 are implemented and verified. Post-Task 013 live E2E startup, capture-lifecycle, and live-UI cleanup fixes are also implemented and verified.

The app is now a native macOS menu bar agent with a transparent AppKit subtitle overlay MVP, protocol-backed mock/test scaffolding, a Core Audio process-tap proof of life, an audio preprocessing path, a simple energy-based VAD/chunker, local WhisperKit ASR diagnostics, a live subtitle session path, and selectable mock or Apple Translation backends. It can show/hide the overlay, lock/unlock click-through behavior, move/resize the overlay in edit mode, persist the overlay frame and lock state, reset the overlay position, start/stop system-output audio capture from Settings, display RMS/peak, chunk-flow diagnostics, VAD/speech activity diagnostics, and local ASR diagnostics, and run `Core Audio -> VAD speech chunks -> WhisperKitASRService -> TranslationRouterService -> SubtitleCoordinator -> overlay` when the supported live settings are selected. Visible app controls now focus on live subtitles; mock pipeline controls have been removed from the menu bar and Settings UI.

It declares the system audio capture usage description and may trigger the macOS system audio recording prompt when capture starts. The app remains sandboxed and now declares outbound network access plus runtime exceptions for `com.apple.audioanalyticsd`, `com.apple.dnssd.service`, and read-only access to `/Library/Preferences/com.apple.networkd.plist` so first-run WhisperKit model download and Apple Translation asset preparation can proceed under Xcode signing. Phase 5 emits model-ready continuous 16 kHz mono Float32 `AudioChunk` values for diagnostics only. Phase 6 keeps those continuous chunks intact and adds separate speech activity events that suppress silence for ASR input. Phase 7 routes those speech chunks to local WhisperKit ASR diagnostics when `Local WhisperKit` is selected. Phase 8 forwards the same ASR events to the overlay, and Phase 9 lets that translation step use Apple Translation or mock translation. Remote LAN inference, raw audio persistence, model benchmarking, and a dedicated diagnostics UI remain out of scope.

## Completed Work

### Documentation

- Added root-level `AGENTS.md` so future Codex sessions have repo-level guidance.
- Surveyed the skeleton Xcode project and the `project_docs` documentation pack.
- Captured implementation order, architecture principles, privacy boundaries, testing guidance, and build commands in `AGENTS.md`.

### Phase 0 App Shell

- Replaced the stock SwiftData starter app with a SwiftUI `MenuBarExtra` app.
- Removed the starter `ContentView` and `Item` model.
- Added a menu bar item labeled "Live Subtitle Translator".
- Added initial menu actions for the mock pipeline, settings, and quit.
- Added a SwiftUI Settings scene.
- Configured the generated app Info.plist to use `LSUIElement = YES`, making the app a menu bar agent with no Dock icon.
- Kept `MACOSX_DEPLOYMENT_TARGET = 26.5` as requested.

### Phase 1 Subtitle Overlay MVP

- Added `SubtitleOverlayWindowController` using a transparent, borderless AppKit `NSPanel`.
- Hosted `SubtitleOverlayView` in the panel with readable Chinese subtitle styling.
- Added locked mode where the overlay ignores mouse events.
- Added edit mode with a visible border, drag behavior, and resize behavior.
- Persisted overlay frame and lock state in `AppSettings`.
- Added frame sanitization and reset behavior for offscreen or invalid overlay positions.
- Added `SubtitleDisplayState` and `SubtitleDisplayModel`.
- Added `MockSubtitleTicker` with the documented mock Chinese subtitle lines.
- Wired menu bar and settings controls:
  - Show/Hide Overlay
  - Lock/Unlock Overlay
  - Reset Overlay Position
  - Start/Stop Mock Subtitles
- Starting mock subtitles shows the overlay and emits a subtitle immediately.
- Stopping mock subtitles cancels the ticker and clears displayed text without hiding the overlay.

### Phase 2 Mock Pipeline Skeleton

- Added core protocol-facing models:
  - `AudioChunk`
  - `AudioSource`
  - `AudioCaptureState`
  - `TranscriptSegment`
  - `TranslationSegment`
  - `ASREvent`
  - `ASRConfiguration`
- Added service protocols:
  - `AudioCaptureService`
  - `ASRService`
  - `TranslationService`
- Added deterministic `MockASRService` that emits scripted partial, stable partial, and final English transcript events.
- Added deterministic `MockTranslationService` that maps known mock English lines to Simplified or Traditional Chinese and records context passed to translation requests.
- Added `SubtitleCoordinator` as the mock pipeline lifecycle owner.
- The coordinator starts/stops mock ASR, consumes `AsyncStream` ASR events, translates final and stable partial segments, ignores unstable partials, maintains recent final transcript context, suppresses duplicate translated subtitles, updates the overlay display model, and clears final subtitles after a hold duration.
- Added `SubtitleStabilizer` for duplicate suppression and context retention.
- Added `SubtitleLineWrapper` with Chinese-oriented defaults of 18 characters per line and 2 lines, truncating overflow with `...`.
- Added minimal in-memory `MetricsRecorder` for ASR, translation, and overlay render timestamps.
- Updated menu bar and settings actions to use `Start Mock Pipeline` and `Stop Mock Pipeline` for Phase 2.
- The mock pipeline still exists as protocol/test scaffolding, but its visible controls were later removed from the menu bar and Settings once the live subtitle path became the primary app flow.
- Kept `MockSubtitleTicker` as a Phase 1 utility/test artifact, no longer the primary menu flow.

### Phase 3 Audio Permission and Diagnostics Placeholders

- Added `NSAudioCaptureUsageDescription` to the app target's generated Info.plist build settings for Debug and Release.
- Added `AudioCapturePermissionStatus`, `AudioSourceAvailabilityStatus`, `AudioCaptureDiagnosticsState`, and `AudioCaptureDiagnosticsModel`.
- Added deterministic status-only defaults:
  - Permission: `Not Requested`
  - Capture State: `Idle`
  - Source Availability: `Placeholder Only`
- Updated the existing Settings Audio section to show permission, capture state, and source availability rows.
- Kept the existing Audio Source picker as the source selection placeholder.
- Did not add permission requests, System Settings links, Core Audio taps, real source enumeration, model integrations, or LAN networking.

### Phase 4 Core Audio Capture Proof Of Life

- Added `ProcessTapAudioCaptureService` behind the existing `AudioCaptureService` protocol.
- Implemented a private stereo global `CATapDescription` with `CATapUnmuted`, pinned to the current default output device UID/stream so browser/video playback follows the audible Mac output; Phase 5 preprocessing mixes it down to 16 kHz mono chunks.
- Created a private aggregate device containing the current system output device as the main subdevice/clock source, then attached the tap through `kAudioAggregateDevicePropertyTapList` to match Apple's documented tap-linking flow.
- Added retry/wait handling around IOProc creation and aggregate-device start so capture startup tolerates Core Audio's brief aggregate initialization window.
- Switched the capture aggregate device to a tap-only input composition with an empty physical subdevice list, which matches working Core Audio tap examples and avoids starting an output-device-backed aggregate that reports `Capturing` without delivering tap samples.
- Added reverse-order cleanup for IOProc, aggregate device, and tap on stop/deinit.
- Kept the audio callback scoped to level metering: it computes RMS/peak snapshots and yields diagnostics without ASR, translation, UI calls, logging, or raw audio persistence.
- Left `audioChunks` unused for Phase 4; model-ready chunk emission was added in Phase 5.
- Added Core Audio process source listing for preparation while keeping actual capture limited to `System Output`.
- Extended `AudioSource` with optional process object ID, PID, and bundle ID metadata.
- Added a clear selected-app unsupported status telling users to choose `System Output` for Phase 4.
- Extended `AudioCaptureDiagnosticsModel` to own the capture service and expose `refreshSources()`, `startCapture(audioSourceOption:)`, and `stopCapture()`.
- Updated Settings with Start/Stop Capture controls, source refresh, source count, capture state, last error, RMS, and peak.
- Added Audio Callbacks and Captured Frames diagnostics so a silent capture session can distinguish "Core Audio callback is not firing" from "callback is firing but buffers are silent."
- Added a non-fatal Capture Warning row when chunks are flowing but captured RMS/peak remain silent, pointing users to macOS system audio recording permission and output-device routing.
- Added normalized and dBFS display values for RMS/peak, including `-∞ dBFS` for silence.
- Added `AudioLevelSnapshot`, `AudioLevelCalculator`, and `AudioCaptureError` for testable metering and diagnostics.

### Phase 5 Audio Preprocessing Chunks

- Added `AudioRingBuffer`, a fixed-capacity 10-second Float32 PCM ring buffer with queue-depth and dropped-frame diagnostics.
- Kept the Core Audio callback minimal: it computes RMS/peak as before and copies Float32 samples into the ring buffer without UI work, ASR, translation, disk writes, or network calls.
- Added `AudioResampler`, using `AVAudioConverter` to convert captured Float32 PCM into deterministic 16 kHz mono Float32 samples.
- Added `AudioChunkAssembler` to accumulate resampled samples into 1-second `AudioChunk` values, normally 16,000 samples each, discarding partial carryover on stop/reset.
- Updated `ProcessTapAudioCaptureService` with a background preprocessing task that drains the ring buffer, resamples/mixes down audio, assembles chunks, yields `audioChunks`, and resets buffers on stop.
- Added `AudioPreprocessingDiagnostics` with emitted chunk count, last chunk duration, queue depth frames, and dropped frames.
- Extended `AudioCaptureDiagnosticsModel` to observe `audioChunks` and preprocessing diagnostics for display only.
- Updated Settings Audio diagnostics to show chunk count, last chunk duration, queue depth, and dropped frames.
- Captured audio chunks are not sent to ASR, translation, subtitles, disk, or LAN services.

### Phase 6 Simple Energy VAD and Speech Chunker

- Added `VoiceActivitySettings` with persisted VAD sensitivity and final-silence duration.
- Added backward-compatible decoding so older settings without VAD fields load with deterministic defaults.
- Added `VADSensitivity` threshold mappings:
  - High: start RMS `0.008`, continue RMS `0.004`
  - Balanced: start RMS `0.015`, continue RMS `0.008`
  - Low: start RMS `0.030`, continue RMS `0.015`
- Added `SpeechActivityEvent`, `SpeechSegmentMetadata`, and `VoiceActivityDiagnostics`.
- Added pure `EnergyVoiceActivityDetector` that uses `AudioLevelCalculator` over 16 kHz mono `AudioChunk.samples`.
- The detector emits `.speechStarted`, `.speechChunk`, and `.speechEnded` events, suppresses silent chunks from speech output, and ends an active segment after configurable final silence.
- Extended `AudioCaptureService` with separate `speechActivityEvents` and `voiceActivityDiagnostics` streams while keeping continuous `audioChunks` unchanged.
- Updated `ProcessTapAudioCaptureService` so VAD runs in the background preprocessing task after chunk assembly, never in the Core Audio callback.
- Updated capture stop/reset behavior to clear VAD state and diagnostics without flushing anything to ASR.
- Extended `AudioCaptureDiagnosticsModel` to observe speech events and VAD diagnostics for Settings display only.
- Updated Settings with VAD sensitivity and final-silence controls plus VAD state, speech chunks, completed speech segments, last speech duration, current silence duration, VAD RMS, and VAD peak.
- Captured speech activity is sent to WhisperKit ASR diagnostics when `Local WhisperKit` is selected, and Phase 8 forwards resulting ASR events to mock translation and the overlay. Speech chunks are still not written to disk or sent to LAN services.

### Phase 7 Local WhisperKit ASR Integration

- Added the SwiftPM dependency `argmax-oss-swift` at version `1.0.0`, product `WhisperKit`, to the app target.
- Added `Package.resolved` pins for `argmax-oss-swift` and `swift-argument-parser`.
- Added `WhisperKitASRService` behind the existing `ASRService` protocol.
- Added `LiveWhisperKitTranscriber`, backed by `WhisperKit(WhisperKitConfig(model: modelID))` and in-memory `transcribe(audioArray:)`.
- Added injectable transcriber support so tests can exercise service lifecycle and transcript/error events without loading a model.
- Added `ASRConfiguration.modelID` and `LocalASRSettings`, defaulting to model ID `tiny`.
- Added Settings model picker values with friendly labels:
  - `tiny` -> WhisperKit model ID `openai_whisper-tiny`
  - `large-v3-v20240930_626MB` -> WhisperKit model ID `openai_whisper-large-v3-v20240930_626MB`
- Legacy persisted model IDs `tiny` and `large-v3-v20240930_626MB` are upgraded to WhisperKit's canonical model IDs on decode.
- Added `ASRDiagnosticsState` with lifecycle state, backend, model ID, accepted speech chunk count, completed transcript count, last transcript, and last error.
- Extended `AudioCaptureDiagnosticsModel` to start local ASR when capture starts and the ASR backend is `Local WhisperKit`.
- Routed `.speechChunk` events to `ASRService.acceptAudioChunk(_:)` and `.speechEnded` events to `ASRService.flush()` for diagnostics only.
- Added a periodic ASR flush after about 3 seconds of ongoing speech chunks so continuous audio can produce transcripts even if the simple energy VAD does not emit `speechEnded`.
- Kept the mock pipeline implementation independent; Phase 8 adds a separate live subtitle path for ASR-to-overlay updates through mock translation.

### Phase 8 Live ASR To Mock Translation Overlay

- Added `LiveSubtitleSessionController` as the live subtitle session owner.
- Added Settings and menu bar actions:
  - Start Live Subtitles
  - Stop Live Subtitles
- Live subtitles validate supported requirements before starting:
  - Audio Source: `System Output`
  - ASR Backend: `Local WhisperKit`
  - Translation Backend: `Mock` in Phase 8, with `Apple Translation` also supported after Phase 9
- Starting live subtitles stops the mock pipeline, shows the overlay, puts `SubtitleCoordinator` in external-event listening mode, and starts system-output capture through `AudioCaptureDiagnosticsModel`.
- Added external ASR event mode to `SubtitleCoordinator` so live ASR events can be translated/displayed without starting the coordinator's mock ASR service.
- Kept `AudioCaptureDiagnosticsModel` as the single consumer of `ASRService.events` and added an async ASR event sink so diagnostics and subtitle forwarding share the same event stream.
- Forwarded ASR `.partial`, `.final`, and `.error` events from the live path into `SubtitleCoordinator.handleASREvent(_:)`.
- Live ASR final/stable-partial transcript text is translated by `MockTranslationService`, so unmapped real transcripts display the existing `[模拟翻译] ...` or `[模擬翻譯] ...` fallback.
- Stopping live subtitles stops capture/ASR routing, clears the ASR event sink, cancels coordinator hold timers, clears displayed subtitles, and leaves the overlay visible.
- Mock pipeline services remain available as independent test/development scaffolding, but the visible app UI now exposes live subtitles instead of mock pipeline controls.

### Phase 9 Apple Translation Backend

- Added `AppleTranslationService` behind `TranslationService`.
- Added a fakeable `AppleTranslationClient` seam so unit tests do not invoke real system translation, downloads, or model preparation.
- Mapped English source (`en`) to Simplified Chinese (`zh-Hans`) and Traditional Chinese (`zh-Hant`) targets.
- Checked Apple `LanguageAvailability.status(from:to:)` before translation.
- For supported-but-not-installed pairs, `AppleTranslationService` calls `TranslationSession.prepareTranslation()` before translating so macOS can prepare/download language assets.
- Mapped latency profile to Apple Translation strategy:
  - `fast` and `balanced`: low latency
  - `moreAccurate`: high fidelity
- Added `TranslationRouterService` so the existing Translation Backend picker routes to:
  - Mock Translation
  - Apple Translation
  - a clear Remote LAN not-implemented error
- Updated `AppState` so `SubtitleCoordinator` uses the router instead of a fixed mock translation service.
- Updated live subtitle validation to allow Apple Translation and reject only Remote LAN translation for this phase.
- Extended `SubtitleCoordinator` with non-persisted `lastErrorMessage`.
- Translation errors now set the coordinator error state and show a Settings Pipeline error without falling back to mock translation or overwriting the current subtitle.
- Later successful translations clear the coordinator error.

### Post-Task 013 Live E2E Startup And Capture Lifecycle Fixes

- Added `LiveSubtitleTranslator.entitlements` and wired it into Debug and Release app signing.
- Kept App Sandbox enabled while adding Core Audio input access, outbound client networking, user-selected read-only files, mach lookup exceptions for `com.apple.audioanalyticsd` and `com.apple.dnssd.service`, and read-only access to `/Library/Preferences/com.apple.networkd.plist`.
- Added the Core Audio input entitlement (`com.apple.security.device.audio-input`) because the process tap is exposed as an aggregate-device input stream; the app still does not request microphone capture or read microphone samples.
- Added a TCC-backed system audio recording permission provider using the same `kTCCServiceAudioCapture` preflight/request SPI shape as Apple's Core Audio taps sample. Settings now reports the actual permission state, points denied users to System Settings > Privacy & Security > Screen & System Audio Recording > System Audio Recording Only, and blocks capture with a clear error if permission is denied or unavailable.
- Added an "Open Privacy Settings" button in Settings' Audio section to jump to the nearest macOS privacy pane for recovery.
- Added non-persisted overlay status state so live startup shows visible Chinese status text before the first subtitle arrives.
- Live startup now shows a short overlay error status if validation, ASR/model loading, or capture startup fails; detailed errors remain in Settings diagnostics.
- Live subtitle startup from idle requires local ASR to start before capture begins, while standalone capture can still run for audio-level diagnostics if ASR fails.
- Live subtitle startup now reuses an already-running standalone capture session instead of stopping and recreating the Core Audio tap before ASR starts.
- Stopping live subtitles now detaches ASR routing without stopping a capture session that was already running before live subtitles started.
- Preprocessing diagnostics now propagate Core Audio callback and captured-frame counters into Settings, so a silent run can distinguish "no callbacks" from "callbacks with silent buffers."
- Settings Pipeline diagnostics now show subtitle ASR-event forwarding, translation attempts, translation successes, last subtitle transcript, and last subtitle translation.
- If translation fails before the first subtitle appears, the overlay now switches from the listening status to the subtitle-unavailable status instead of looking stuck.
- First-run live E2E may require internet access to download/cache WhisperKit models and Apple Translation language assets.
- The live listening overlay hint now clears after the first detected non-silent audio activity, leaving the overlay blank until an actual translated subtitle or error arrives.
- Removed `Start Mock Pipeline` and `Stop Mock Pipeline` from both the menu bar dropdown and Settings Pipeline section so live subtitles are the only primary subtitle-start path in the UI.
- Widened the Settings window and split the Audio action controls into two rows so button titles and permission guidance are no longer clipped in the primary diagnostics view.
- Updated live ASR routing so WhisperKit receives continuous 16 kHz mono audio chunks rather than VAD-filtered speech chunks. VAD remains visible as diagnostics and can trigger early flushes, but it no longer drops audio before ASR.
- Locked translation profile and VAD controls while capture/live subtitles are running, with Settings copy explaining that those changes should be made before starting capture.

### Settings

- Added `AppSettings` with placeholder persisted configuration:
  - Audio source
  - ASR backend
  - Translation backend
  - Target language
  - Latency profile
  - Diagnostics enabled
  - Optional remote server URL
  - Overlay frame
  - Overlay lock state
  - Voice activity sensitivity and final-silence duration
- Added `SettingsStore`, backed by `UserDefaults`.
- Added a Settings UI with placeholder backend/audio controls and overlay controls.
- Added backward-compatible decoding for older settings that do not contain overlay or voice activity fields.

### Mock Pipeline

- Added `PipelineState`.
- Added `MockPipelineController`.
- Mock pipeline start/stop is idempotent.
- Phase 0/1 `MockPipelineController`, `MockASRService`, and `MockTranslationService` remain as lightweight test/development artifacts; visible app flow now uses live subtitle controls and `SubtitleCoordinator.pipelineState`.

### Project Structure

Added the intended module folders:

- `LiveSubtitleTranslator/App`
- `LiveSubtitleTranslator/Settings`
- `LiveSubtitleTranslator/Overlay`
- `LiveSubtitleTranslator/AudioCapture`
- `LiveSubtitleTranslator/Speech`
- `LiveSubtitleTranslator/Translation`
- `LiveSubtitleTranslator/Subtitles`
- `LiveSubtitleTranslator/Diagnostics`

All intended module folders now contain at least initial implementation code. Audio capture has a Phase 9 system-output path with preprocessing chunks, speech activity events, local ASR diagnostics, and live ASR-to-overlay forwarding through the translation router. Translation now has mock and Apple backends, and diagnostics has an in-memory metrics recorder plus audio/chunk/VAD/ASR state.

### Tests

- Replaced the placeholder unit test with focused Swift Testing tests.
- Kept a minimal UI launch smoke test suitable for a menu bar agent.

Verified tests:

- Default `AppSettings` values are deterministic.
- `SettingsStore` round-trips through an isolated `UserDefaults` suite.
- Legacy Phase 0 settings decode with default overlay settings.
- `MockPipelineController` start/stop behavior is idempotent.
- `MockSubtitleTicker` cycles through lines deterministically.
- `MockSubtitleTicker` start/stop behavior is idempotent.
- `SubtitleDisplayModel` updates and clears display state.
- `SubtitleDisplayModel` tracks non-subtitle overlay status and clears it on subtitle update/stop.
- `SubtitleOverlayWindowController` show/hide behavior tracks visibility and sanitizes persisted frames.
- `SubtitleOverlayWindowController` lock/unlock and reset behavior persists settings.
- Core Phase 2 pipeline models construct with deterministic defaults.
- `MockASRService` emits scripted transcript events and stops idempotently.
- `MockTranslationService` returns deterministic Chinese and receives recent context.
- `SubtitleCoordinator` updates the overlay for final ASR segments.
- `SubtitleCoordinator` ignores unstable partials.
- `SubtitleCoordinator` displays stable partials with `isPartial = true`.
- `SubtitleCoordinator` can replace a matching stable partial with a final subtitle so the display leaves partial mode.
- `SubtitleCoordinator` suppresses duplicate final subtitle text.
- `SubtitleCoordinator` stop cancels work, clears display, and returns to idle.
- `SubtitleCoordinator` hold timers clear only the current subtitle, not a newer subtitle.
- `SubtitleLineWrapper` covers empty text, one-line output, two-line output, truncation, and mixed punctuation.
- `MetricsRecorder` records stage timestamps by segment ID.
- Audio capture diagnostics placeholders have deterministic defaults and display labels.
- The generated Info.plist build settings contain `NSAudioCaptureUsageDescription` for both app configurations.
- `AudioLevelCalculator` covers silence, known RMS, known peak, negative samples, and empty input.
- `AudioCaptureDiagnosticsModel` covers source refresh, start/stop state changes, selected-app unsupported status, level updates, and error surfacing with a fake capture service.
- `AudioSource` process metadata construction is deterministic.
- `AudioRingBuffer` covers write/read order, interleaved stereo frames, wraparound, overflow drops, reset, and queue-depth diagnostics.
- `AudioResampler` covers 48 kHz mono to 16 kHz mono sample count, stereo mixdown to mono, and empty input.
- `AudioChunkAssembler` covers exact 1-second chunk emission, carryover across appends, partial carryover discard on reset, and host-time propagation.
- `AudioCaptureDiagnosticsModel` covers fake chunk-stream updates for chunk count/duration, queue depth, dropped frames, and reset on stop.
- `VoiceActivitySettings` covers defaults, Codable round trip, threshold mappings, and legacy settings decode fallback.
- `EnergyVoiceActivityDetector` covers silence suppression, first speech start, speech chunks, final-silence end, speech resumption before final silence, sensitivity thresholds, and reset behavior.
- `AudioCaptureDiagnosticsModel` covers speech event stream updates, VAD diagnostics updates, and VAD reset on stop.
- `LocalASRSettings` and `ASRConfiguration` cover model defaults and construction.
- `WhisperKitASRService` covers model loading, idempotent start, stopped/empty input, chunk buffering, flush-to-final transcript, transcription errors, and idempotent stop through an injected fake transcriber.
- `AudioCaptureDiagnosticsModel` covers local-ASR speech routing, `.speechEnded` flush, ASR final/error diagnostics, mock-backend non-routing, and ASR reset on stop.
- `AudioCaptureDiagnosticsModel` forwards ASR events through a single diagnostics-owned event sink.
- `LiveSubtitleSessionController` validates required live subtitle settings and reports clear errors.
- Live subtitle start shows the overlay, starts capture, configures local WhisperKit ASR, and puts `SubtitleCoordinator` in external-event listening mode.
- Live ASR final events update the overlay through mock translation fallback text.
- Live ASR error events update diagnostics and the coordinator error state without crashing capture cleanup.
- Live subtitle stop clears capture/ASR routing, the ASR event sink, coordinator state, and displayed subtitles.
- `AppleTranslationService` covers language mapping, installed translation, supported-pair preparation, unsupported pairs, translation failures, latency strategy mapping, and empty input through an injected fake client.
- `TranslationRouterService` routes mock and Apple translation backends and rejects Remote LAN translation.
- `SubtitleCoordinator` surfaces translation errors without mock fallback and clears the error on a later successful translation.
- `LiveSubtitleSessionController` accepts Apple Translation for live subtitles and still rejects Remote LAN translation.
- Live subtitle startup tests cover visible preparing/listening overlay status and ASR startup failure status.
- Live subtitle startup tests cover clearing the listening overlay hint after first audio activity and not restoring it after subtitle hold clears.
- ASR diagnostics tests cover periodic flushing for ongoing speech without a `speechEnded` event.
- Build-facing tests assert the app target uses the entitlements file and declares sandbox/network/audioanalyticsd/DNS/networkd entitlements.
- The menu bar agent launches under UI testing.

## Verification

These commands passed:

```bash
xcodebuild -project LiveSubtitleTranslator.xcodeproj -scheme LiveSubtitleTranslator -destination 'platform=macOS' build
xcodebuild -project LiveSubtitleTranslator.xcodeproj -scheme LiveSubtitleTranslator -destination 'platform=macOS' test
```

Test result:

- 77 unit tests passed.
- 1 UI launch test passed.

## Not Yet Implemented

- Configurable overlay style settings beyond the Phase 1 default styling.
- Full audio capture permission status probing before/after prompts.
- LAN inference client or server.
- Diagnostics panel and persisted/exported latency metrics.

## Important Current Files

- `AGENTS.md`
- `LiveSubtitleTranslator/App/LiveSubtitleTranslatorApp.swift`
- `LiveSubtitleTranslator/App/AppState.swift`
- `LiveSubtitleTranslator/App/LiveSubtitleSessionController.swift`
- `LiveSubtitleTranslator/App/MenuBarContentView.swift`
- `LiveSubtitleTranslator/App/MockPipelineController.swift`
- `LiveSubtitleTranslator/App/PipelineState.swift`
- `LiveSubtitleTranslator.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `LiveSubtitleTranslator/AudioCapture/AudioCaptureError.swift`
- `LiveSubtitleTranslator/AudioCapture/AudioCaptureService.swift`
- `LiveSubtitleTranslator/AudioCapture/AudioChunkAssembler.swift`
- `LiveSubtitleTranslator/AudioCapture/AudioLevel.swift`
- `LiveSubtitleTranslator/AudioCapture/AudioPreprocessingDiagnostics.swift`
- `LiveSubtitleTranslator/AudioCapture/AudioResampler.swift`
- `LiveSubtitleTranslator/AudioCapture/AudioRingBuffer.swift`
- `LiveSubtitleTranslator/AudioCapture/ProcessTapAudioCaptureService.swift`
- `LiveSubtitleTranslator/AudioCapture/VoiceActivity.swift`
- `LiveSubtitleTranslator/Diagnostics/AudioCaptureDiagnosticsModel.swift`
- `LiveSubtitleTranslator/Diagnostics/ASRDiagnostics.swift`
- `LiveSubtitleTranslator/Diagnostics/MetricsRecorder.swift`
- `LiveSubtitleTranslator/Overlay/SubtitleOverlayView.swift`
- `LiveSubtitleTranslator/Overlay/SubtitleOverlayWindowController.swift`
- `LiveSubtitleTranslator/Settings/AppSettings.swift`
- `LiveSubtitleTranslator/Settings/SettingsStore.swift`
- `LiveSubtitleTranslator/Settings/SettingsView.swift`
- `LiveSubtitleTranslator/Speech/ASRService.swift`
- `LiveSubtitleTranslator/Speech/MockASRService.swift`
- `LiveSubtitleTranslator/Speech/WhisperKitASRService.swift`
- `LiveSubtitleTranslator/Subtitles/MockSubtitleTicker.swift`
- `LiveSubtitleTranslator/Subtitles/SubtitleCoordinator.swift`
- `LiveSubtitleTranslator/Subtitles/SubtitleDisplayModel.swift`
- `LiveSubtitleTranslator/Subtitles/SubtitleDisplayState.swift`
- `LiveSubtitleTranslator/Subtitles/SubtitleLineWrapper.swift`
- `LiveSubtitleTranslator/Subtitles/SubtitleStabilizer.swift`
- `LiveSubtitleTranslator/Translation/TranslationService.swift`
- `LiveSubtitleTranslator/Translation/MockTranslationService.swift`
- `LiveSubtitleTranslator/Translation/AppleTranslationService.swift`
- `LiveSubtitleTranslator/Translation/TranslationRouterService.swift`
- `LiveSubtitleTranslatorTests/LiveSubtitleTranslatorTests.swift`
- `LiveSubtitleTranslatorUITests/LiveSubtitleTranslatorUITests.swift`

## Notes for the Next Session

- The next coding pass should start Task 014 from `project_docs/docs/05_CODEX_TASK_BACKLOG.md`.
- Add latency metrics and diagnostics display/export around capture, chunk emission, ASR, translation, and overlay render timestamps.
- Keep LAN networking, raw audio persistence, and model benchmarking out of Task 014 unless a new plan explicitly expands scope.
