# 04 — Implementation Plan

Prepared: 2026-05-20

This plan is designed to let Codex build the app incrementally without getting blocked by models or audio permissions too early.

## Phase 0 — Repo and project setup

Status: Complete and verified as of 2026-05-20.

Goal: Create a compilable macOS Xcode project with documentation and basic structure.

Tasks:

1. Create native macOS app project.
2. Set deployment target.
3. Add menu bar entry point.
4. Add settings store.
5. Add module folders.
6. Add mock services.
7. Add initial unit tests.

Deliverables:

- App launches.
- Menu bar icon appears.
- Settings window opens.
- Mock pipeline can be started/stopped.

Do not integrate audio or models yet.

## Phase 1 — Subtitle overlay MVP

Status: Complete and verified as of 2026-05-20.

Goal: Build the overlay UX before doing real inference.

Tasks:

1. Create `SubtitleOverlayWindowController`.
2. Create transparent borderless overlay window.
3. Host SwiftUI `SubtitleOverlayView` inside AppKit window.
4. Add locked mode: click-through overlay.
5. Add edit mode: visible border, drag, resize.
6. Persist overlay frame.
7. Add mock subtitle ticker.

Acceptance criteria:

- Overlay appears above ordinary windows.
- Overlay can be moved and resized.
- Overlay can be locked/unlocked.
- Overlay frame persists after relaunch.
- Mock Chinese subtitle lines render cleanly.

Suggested mock lines:

```text
我们今晚要去哪里？
我不知道，但先离开这里。
这不是一个好主意。
等等，我听到有人来了。
```

## Phase 2 — Pipeline skeleton

Status: Complete and verified as of 2026-05-20.

Goal: Connect app state, mock ASR, mock translation, and overlay through real service protocols.

Tasks:

1. Implement `ASRService` protocol.
2. Implement `TranslationService` protocol.
3. Implement `SubtitleCoordinator`.
4. Add `SubtitleStabilizer`.
5. Add diagnostics timestamps.
6. Add unit tests for duplicate suppression and line wrapping.

Acceptance criteria:

- Mock ASR emits partial and final English segments.
- Mock translation returns Chinese text.
- Coordinator updates overlay.
- Partial/final behavior is testable.
- Metrics record timestamps for each segment.

Implemented notes:

- `AudioCaptureService`, `ASRService`, and `TranslationService` now exist behind protocol-facing models.
- `MockASRService` and `MockTranslationService` provide deterministic testable behavior.
- `SubtitleCoordinator` owns the mock pipeline lifecycle and updates the existing overlay display model.
- `SubtitleLineWrapper`, `SubtitleStabilizer`, and in-memory `MetricsRecorder` cover the Phase 2 utility needs.

## Phase 3 — Audio permission and diagnostics placeholders

Status: Complete and verified as of 2026-05-20.

Goal: Add permission/status plumbing for future system audio capture without starting a Core Audio tap.

Tasks:

1. Add `NSAudioCaptureUsageDescription` to the generated Info.plist settings with a clear reason for capturing system audio.
2. Add a diagnostics/settings surface for audio capture permission status placeholders.
3. Add source selection placeholders for system output and future per-process capture.
4. Add lightweight state models needed by the placeholder UI.
5. Add tests for any new settings/state behavior.

Acceptance criteria:

- Project builds.
- Settings or diagnostics UI shows audio capture permission/status placeholders.
- Source selection UI is clearly placeholder-only.
- No Core Audio tap, real audio capture, ASR model, Apple Translation, or LAN networking is introduced.

Implemented notes:

- The app target's generated Info.plist build settings include `NSAudioCaptureUsageDescription` for Debug and Release.
- Settings shows status-only rows for permission, capture state, and source availability.
- Audio source selection remains a placeholder picker; no real source enumeration or permission request happens yet.

## Phase 4 — Core Audio capture proof of life

Status: Complete and verified as of 2026-05-20.

Goal: Capture real Mac output audio and prove it with diagnostics, not ASR.

Tasks:

1. Implement process/app audio source listing for preparation.
2. Implement `ProcessTapAudioCaptureService` using Core Audio taps.
3. Create private aggregate device and IOProc callback.
4. Compute RMS/peak levels in the callback while leaving ring buffer work to Phase 5.
5. Add RMS/peak meter in diagnostics.
6. Add start/stop cleanup.

Acceptance criteria:

- User can start capture.
- App requests/uses system audio capture permission.
- RMS meter reacts to video audio.
- Stop releases the tap and aggregate device.
- App does not crash when output device changes or no audio is playing.

Implemented notes:

- `ProcessTapAudioCaptureService` creates a private stereo global process tap pinned to the current default output device UID/stream, a private aggregate device clocked from that output device, and an IOProc block. It attaches the tap through `kAudioAggregateDevicePropertyTapList` and retries IOProc creation/device start during Core Audio's aggregate initialization window. Phase 5 preprocessing mixes capture down to 16 kHz mono.
- Settings is the only UI surface for this phase: Start/Stop Capture, Refresh Sources, source count/status, capture state, last error, RMS, and peak.
- Settings also surfaces a non-fatal Capture Warning when chunk flow is alive but captured levels stay silent, which usually points to macOS Audio Capture permission or output-device routing.
- Audio Capture permission is preflighted/requested through a small TCC-backed provider using `kTCCServiceAudioCapture`, matching Apple's Core Audio taps sample behavior. Capture is blocked with a Settings error when permission is denied or unavailable.
- Capture is limited to `System Output`; `Selected App` reports a clear unsupported Phase 4 status.
- Source listing includes `System Output` plus Core Audio process objects where available.
- Phase 4 left `audioChunks` unused; Phase 5 adds chunk emission. No captured audio is sent to ASR, translation, subtitles, disk, or LAN services.

## Phase 5 — Audio preprocessing

Status: Complete and verified for Task 009 as of 2026-05-20. Simple VAD/silence suppression is implemented separately in Phase 6 / Task 010.

Goal: Convert captured audio into model-ready chunks.

Tasks:

1. Implement `AudioRingBuffer`. Complete.
2. Implement `AudioResampler` using `AVAudioConverter`. Complete.
3. Mix down to mono. Complete.
4. Convert to 16 kHz Float32. Complete.
5. Emit 1-second `AudioChunk` values with timestamps. Complete.
6. Add chunk-flow diagnostics for count, duration, queue depth, and dropped frames. Complete.
7. Add tests for ring-buffer behavior, resampling, chunk assembly, and diagnostics. Complete.
8. Add basic energy-based VAD. Complete in Phase 6 / Task 010.

Acceptance criteria:

- Model input chunks are 16 kHz mono.
- Chunks are emitted at predictable cadence.
- Continuous chunks remain available for diagnostics; silence suppression is handled by a separate Phase 6 speech activity stream.
- Diagnostics show chunk duration and queue depth.

Implemented notes:

- `ProcessTapAudioCaptureService` now writes captured Float32 samples into a fixed-capacity `AudioRingBuffer` from the callback while continuing to compute RMS/peak.
- A background preprocessing task drains the ring buffer, uses `AVAudioConverter` through `AudioResampler`, assembles 1-second 16 kHz mono `AudioChunk` values, and yields them through `AudioCaptureService.audioChunks`.
- Settings shows emitted chunk count, last chunk duration, queue depth frames, and dropped frames alongside existing capture/RMS/peak diagnostics.
- Chunks are diagnostics-only in this phase: no ASR, translation, subtitle rendering, LAN networking, or raw audio persistence consumes them.

Phase 6 builds on this with a separate VAD/chunker path before local ASR integration.

## Phase 6 — Simple VAD/chunker

Status: Complete and verified for Task 010 as of 2026-05-20.

Goal: Suppress silence for future ASR consumption without changing continuous audio chunk diagnostics.

Tasks:

1. Add `VoiceActivitySettings` with VAD sensitivity and final-silence duration. Complete.
2. Add deterministic RMS threshold mappings for high, balanced, and low sensitivity. Complete.
3. Add speech activity primitives for speech start, speech chunk, and speech end events. Complete.
4. Implement `EnergyVoiceActivityDetector` over 16 kHz mono `AudioChunk` values. Complete.
5. Keep `audioChunks` continuous while adding separate speech activity and VAD diagnostics streams. Complete.
6. Run VAD in the background preprocessing task after chunk assembly, never in the Core Audio callback. Complete.
7. Add Settings controls and diagnostics rows for VAD state, speech chunks, completed speech segments, last speech duration, current silence duration, and VAD RMS/peak. Complete.
8. Add focused unit tests for settings, detector behavior, and diagnostics model updates. Complete.

Acceptance criteria:

- Continuous audio chunk diagnostics remain unchanged.
- Silent chunks do not emit speech chunk events.
- Speech start/end and configurable final-silence behavior are testable.
- VAD diagnostics are visible in Settings.
- No WhisperKit, ASR routing, translation, subtitle rendering, LAN networking, or raw audio persistence is introduced.

Implemented notes:

- `AudioCaptureService` now exposes `speechActivityEvents` and `voiceActivityDiagnostics` alongside continuous `audioChunks`.
- `ProcessTapAudioCaptureService` snapshots VAD settings on capture start, processes assembled 1-second chunks through `EnergyVoiceActivityDetector`, and resets VAD diagnostics on stop.
- Future ASR should consume `.speechChunk` events rather than raw continuous `audioChunks`.

Follow-up:

- Task 011 integrates WhisperKit / Argmax OSS behind `ASRService`. Complete in Phase 7.

## Phase 7 — Local ASR integration

Status: Complete and verified for Task 011 as of 2026-05-20. Initial ASR output was diagnostics-only; Task 012 later wired it to mock translation and the overlay.

Goal: Use a real local ASR backend on the M4 Max.

Tasks:

1. Add Argmax OSS / WhisperKit Swift package. Complete.
2. Implement `WhisperKitASRService`. Complete.
3. Load a small/debug model first. Complete with friendly `tiny` default mapped to WhisperKit model ID `openai_whisper-tiny`.
4. Route preprocessed speech chunks to ASR. Complete for diagnostics-only local ASR.
5. Emit final transcript events and errors. Complete.
6. Add model selection setting. Complete for friendly labels `tiny` and `large-v3-v20240930_626MB`, mapped internally to `openai_whisper-tiny` and `openai_whisper-large-v3-v20240930_626MB`.
7. Benchmark tiny/base/small/large-v3-turbo or available recommended models. Deferred.

Acceptance criteria:

- App can route captured speech chunks to local WhisperKit ASR when Local WhisperKit is selected.
- Model loading failures surface as ASR diagnostics without stopping capture.
- ASR events appear in diagnostics.
- The app can stop/restart ASR without relaunching.

Notes:

- Start with English language forced when watching English content.
- Use smaller models while building; benchmark larger models later.
- Phase 7 uses segment-style flushes after VAD speech end. Overlay updates were added in Task 012.

Implemented notes:

- Added `argmax-oss-swift` SwiftPM package at version `1.0.0`, product `WhisperKit`.
- Added `WhisperKitASRService`, `LiveWhisperKitTranscriber`, and injectable transcriber test seams.
- Added `LocalASRSettings` and `ASRConfiguration.modelID`, with `tiny` as the default model.
- Extended Settings and diagnostics with ASR state, backend, model, accepted speech chunks, transcript count, last transcript, and ASR error.
- Local ASR consumes `speechActivityEvents` only when the ASR backend is `Local WhisperKit`.

Follow-up:

- Task 012 wires Core Audio + VAD + WhisperKit ASR through mock translation and the overlay. Complete in Phase 8.

## Phase 8 — Live ASR to mock translation overlay

Status: Complete and verified for Task 012 as of 2026-05-21. Initial live ASR reached the overlay only through mock translation; Apple Translation was added in Task 013.

Goal: Connect real local ASR transcript events to the existing subtitle overlay without adding a real translation backend yet.

Tasks:

1. Add a live subtitle session controller. Complete.
2. Validate `System Output`, `Local WhisperKit`, and `Mock` translation before starting. Complete.
3. Start system-output capture through the audio diagnostics model. Complete.
4. Keep `AudioCaptureDiagnosticsModel` as the single ASR event consumer. Complete.
5. Forward the same ASR events to `SubtitleCoordinator`. Complete.
6. Add coordinator external-event mode so live ASR does not start mock ASR. Complete.
7. Add Settings and menu bar Start/Stop Live Subtitles controls. Complete.
8. Keep mock pipeline controls unchanged for the initial Phase 8 handoff. Complete; these visible controls were later removed after live E2E became the primary app path.

Acceptance criteria:

- Starting live subtitles shows the overlay and starts system-output capture when required settings are selected.
- ASR final/stable-partial events are translated by `MockTranslationService` and rendered in the overlay.
- ASR diagnostics still update from the same event stream.
- Stop cancels capture/ASR routing, clears subtitle text, and leaves the overlay visible.

Implemented notes:

- Added `LiveSubtitleSessionController`.
- Added `SubtitleCoordinator.startExternalEvents()` and `stopExternalEvents()`.
- Added `AudioCaptureDiagnosticsModel.asrEventSink`.
- Unknown real ASR transcript text displays the existing mock translation fallback, for example `[模拟翻译] transcript`.
- Mock pipeline services remain in the codebase as test/development scaffolding, but the menu bar and Settings UI now expose live subtitle controls instead of mock pipeline controls.

Follow-up:

- Task 013 implements Apple Translation behind `TranslationService`. Complete in Phase 9.

## Phase 9 — Translation integration

Status: Complete and verified for Task 013 as of 2026-05-21. Apple Translation is selectable; Remote LAN translation remains future work.

Goal: Convert English transcript segments into Chinese subtitles.

Tasks:

1. Implement `AppleTranslationService`. Complete.
2. Use `LanguageAvailability` to validate English → Simplified Chinese and English → Traditional Chinese. Complete.
3. Prepare supported language assets with `prepareTranslation()`. Complete.
4. Route the Settings translation backend to Mock or Apple Translation. Complete.
5. Surface Apple Translation failures clearly without automatic mock fallback. Complete.
6. Add tests for Apple Translation mapping, availability, preparation, routing, and coordinator error handling. Complete.

Acceptance criteria:

- English ASR output becomes Chinese overlay text.
- Translation errors surface in Settings without stopping ASR/capture.
- User can choose Simplified or Traditional Chinese if backend supports it.
- Subtitle output remains concise.

Implemented notes:

- Added `AppleTranslationService`, `LiveAppleTranslationClient`, and `TranslationRouterService`.
- `fast` and `balanced` use Apple's low-latency strategy; `moreAccurate` uses high-fidelity strategy.
- Remote LAN translation returns a clear not-implemented error.
- Translation context is still passed through the service protocol but is not used by Apple Translation in this phase.
- Post-Task 013 live E2E startup fix added sandbox entitlements for outbound downloads plus runtime exceptions for `com.apple.audioanalyticsd`, `com.apple.dnssd.service`, and read-only access to `/Library/Preferences/com.apple.networkd.plist` while keeping App Sandbox enabled.
- Live startup now renders non-subtitle overlay status/error text before the first translated subtitle, so startup/download failures are visible even when no subtitle has arrived.
- Live ASR now auto-flushes after about 3 seconds of ongoing speech chunks, so continuous audio does not have to wait for a VAD `speechEnded` event before producing subtitles.
- First-run live E2E may need internet access to download/cache WhisperKit models and Apple Translation language assets; cached assets may work offline afterward.
- The live listening status clears after the first detected non-silent audio activity, leaving the overlay blank until a translated subtitle or error is ready.

Next task:

- Task 014 adds latency metrics and diagnostics display/export.

## Phase 10 — End-to-end local MVP

Goal: Make the personal-use app watchable.

Tasks:

1. Wire Core Audio → ASR → Translation → Overlay.
2. Add latency profile controls.
3. Add diagnostics panel.
4. Add user-visible permission/help messages.
5. Test with Safari/Chrome/TV/VLC/IINA.
6. Tune subtitle stabilizer.

Acceptance criteria:

- A video playing on the Mac produces live Chinese subtitles.
- Latency usually stays under 5 seconds.
- Overlay is readable and does not block playback controls when locked.
- Start/stop works repeatedly.

## Phase 11 — Optional LAN inference server

Goal: Use the NVIDIA GPUs for faster/better ASR and translation.

Tasks:

1. Implement FastAPI/WebSocket server.
2. Add faster-whisper ASR backend.
3. Add CTranslate2 translation backend.
4. Add remote Mac client.
5. Add reconnection and error handling.
6. Benchmark Mac-local vs LAN.

Acceptance criteria:

- Mac app can connect to LAN server.
- Audio streams to server.
- Server returns transcript and translated subtitle events.
- End-to-end latency is competitive with local backend.
- Server can be swapped without changing overlay/audio code.

## Phase 12 — Polish and hardening

Goal: Improve reliability for daily personal use.

Tasks:

1. Add app/source allowlist and exclusion list.
2. Handle output-device changes.
3. Add settings import/export.
4. Add model download/status UI.
5. Add crash-safe cleanup for taps.
6. Add benchmark report export.
7. Add more overlay styles.

Acceptance criteria:

- App can run through a full TV episode without manual intervention.
- Recoverable errors provide clear UI.
- Performance logs identify bottlenecks.

## Suggested milestones

| Milestone | Expected result |
|---|---|
| M1 | Menu bar app + movable overlay + mock subtitles. |
| M2 | Mock pipeline with ASR/translation protocols and diagnostics. |
| M3 | Audio permission/status placeholders. |
| M4 | Core Audio capture proof-of-life with RMS meter. |
| M5 | Audio preprocessing emits chunks and VAD speech events. |
| M6 | Local WhisperKit ASR transcribes audio. |
| M7 | Local Chinese subtitles render end-to-end. |
| M8 | LAN inference server works as optional backend. |
| M9 | Benchmark-tuned personal-use build. |

## Build strategy for Codex

Ask Codex to complete one milestone at a time. Do not ask for the full product in one pass.

Good pattern:

```text
Implement Phase 1 from docs/04_IMPLEMENTATION_PLAN.md.
Do not implement audio or ASR yet.
Use mock subtitle text.
Keep the app compiling after this task.
Add or update tests if useful.
```

Bad pattern:

```text
Build the whole live subtitle translator app.
```
