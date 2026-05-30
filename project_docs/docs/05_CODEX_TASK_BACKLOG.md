# 05 — Codex Task Backlog

Prepared: 2026-05-20

Use these as incremental Codex prompts. Each task is scoped so Codex can implement and verify one part of the application at a time.

## Task 001 — Create macOS project skeleton

Status: Complete and verified as of 2026-05-20.

Prompt:

```text
Create a native macOS Xcode project named LiveSubtitleTranslator. Use Swift, SwiftUI, and AppKit. Add the folder/module structure described in AGENTS.md. The app should launch, show a menu bar item, and include a Settings window with placeholder controls for source, ASR backend, translation backend, target language, and diagnostics. Do not implement audio capture or models yet.
```

Acceptance criteria:

- Project builds.
- App launches.
- Menu bar item exists.
- Settings window opens.
- Placeholder settings are persisted with `UserDefaults` or a small Codable store.

## Task 002 — Implement subtitle overlay window

Status: Complete and verified as of 2026-05-20.

Prompt:

```text
Implement Phase 1 from docs/04_IMPLEMENTATION_PLAN.md. Create SubtitleOverlayWindowController using AppKit. It should create a transparent, borderless overlay window hosting a SwiftUI SubtitleOverlayView. Add locked mode where the overlay ignores mouse events and edit mode where it can be dragged/resized. Persist frame and lock state.
```

Acceptance criteria:

- Overlay appears.
- It renders mock Chinese subtitle text.
- It can be moved/resized in edit mode.
- It is click-through in locked mode.
- Position and size persist after restart.

## Task 003 — Add mock subtitle ticker

Status: Complete and verified as of 2026-05-20.

Prompt:

```text
Add a MockSubtitleTicker that emits Chinese subtitle lines every few seconds. Wire it to the overlay through an observable SubtitleDisplayState. Add menu actions to show/hide overlay, lock/unlock overlay, and start/stop mock subtitles.
```

Acceptance criteria:

- Mock lines update on the overlay.
- Menu actions work.
- No real audio/model dependencies.

## Task 004 — Add pipeline protocols and data models

Status: Complete and verified as of 2026-05-20.

Prompt:

```text
Implement the core data models and service protocols from docs/03_ARCHITECTURE.md: AudioChunk, TranscriptSegment, TranslationSegment, SubtitleDisplayState, AudioCaptureService, ASRService, TranslationService. Add mock implementations for ASR and Translation. Keep the app compiling.
```

Acceptance criteria:

- Protocols compile.
- Mock ASR emits partial and final transcript segments.
- Mock Translation returns deterministic Chinese text.
- No real audio/model dependencies.

## Task 005 — Implement SubtitleCoordinator

Status: Complete and verified as of 2026-05-20.

Prompt:

```text
Implement SubtitleCoordinator. It should consume ASREvent values, maintain recent context, call TranslationService for final or stable transcript segments, and publish SubtitleDisplayState to the overlay. Include a simple duplicate suppression mechanism.
```

Acceptance criteria:

- Mock ASR → Mock Translation → Overlay works.
- Duplicate text is suppressed.
- Final subtitles remain visible for a configurable hold time.
- Unit tests cover duplicate suppression and basic final segment flow.

## Task 006 — Implement subtitle line wrapping and style settings

Status: Partially complete as of 2026-05-20. The `SubtitleLineWrapper` utility and wrapping tests are implemented; configurable overlay style settings remain future work.

Prompt:

```text
Add overlay style settings: font size, max lines, background opacity, corner radius, text shadow toggle, and max Chinese characters per line. Implement a simple Chinese subtitle line wrapping utility and unit tests.
```

Acceptance criteria:

- Settings update the overlay live.
- Long Chinese lines wrap into one or two lines.
- Unit tests cover wrapping behavior.

## Task 007 — Add audio capture permission plumbing

Status: Complete and verified as of 2026-05-20.

Prompt:

```text
Add Info.plist key NSAudioCaptureUsageDescription with a clear reason for capturing system audio. Add a diagnostics view that shows audio capture permission/status placeholders and a source selection placeholder. Do not implement the Core Audio tap yet.
```

Acceptance criteria:

- Info.plist includes the audio capture usage description.
- Settings/diagnostics UI shows permission status placeholder.
- Project builds.

## Task 008 — Implement Core Audio process tap proof-of-life

Status: Complete and verified as of 2026-05-20.

Prompt:

```text
Implement ProcessTapAudioCaptureService using Core Audio process taps. Use Apple's Core Audio taps sample and the AudioCap sample as references. The first goal is proof-of-life: capture audio from a selected process or system output, compute RMS/peak levels, and display them in diagnostics. Do not connect to ASR yet. Ensure stop cleans up taps, aggregate devices, and IOProc IDs.
```

Acceptance criteria:

- Starting capture produces RMS changes when video audio plays.
- Stopping capture releases resources.
- Missing permission or tap failure produces a clear error.
- Audio callback does minimal work.

Implemented notes:

- `ProcessTapAudioCaptureService` supports Phase 4 system-output capture with a private stereo global process tap pinned to the current default output device UID/stream, a private aggregate device clocked from that output device, explicit tap-list property attachment, retry-tolerant IOProc startup, and reverse-order cleanup. Phase 5 preprocessing mixes capture down to 16 kHz mono.
- Settings exposes Start/Stop Capture, Refresh Sources, source count/status, capture state, last error, RMS, and peak.
- Settings shows a Capture Warning if chunks are emitted but captured levels stay silent, to distinguish a live-but-silent tap from a stopped capture path.
- Audio Capture permission is preflighted/requested via `kTCCServiceAudioCapture`; Settings reports the actual permission state instead of inferring authorization from a started tap.
- Process source metadata is listed for preparation, but selected-process capture intentionally remains unsupported in Phase 4.
- Captured audio is not written to disk and is not sent to ASR, translation, subtitles, or LAN services.

## Task 009 — Implement audio ring buffer and resampler

Status: Complete and verified as of 2026-05-20.

Prompt:

```text
Implement AudioRingBuffer and AudioResampler. Convert captured audio into 16 kHz mono Float32 AudioChunk values. Use AVAudioConverter for resampling/mixdown. Add diagnostics for chunk duration, queue depth, and dropped frames.
```

Acceptance criteria:

- Chunks are emitted at a predictable cadence.
- Output chunks are 16 kHz mono.
- Diagnostics show chunk flow.
- No heavy work happens in the Core Audio callback.

Implemented notes:

- Added `AudioRingBuffer` with fixed capacity, queue-depth diagnostics, dropped-frame accounting, reset behavior, and nonblocking callback write support.
- Added `AudioResampler` using `AVAudioConverter` to convert captured Float32 PCM to deterministic 16 kHz mono Float32 samples.
- Added `AudioChunkAssembler` for 1-second chunks with source host-time propagation and partial carryover discard on reset.
- Updated `ProcessTapAudioCaptureService` so the audio callback computes RMS/peak and copies samples into the ring buffer, while a background task drains, resamples, assembles, and yields `audioChunks`.
- Added `AudioPreprocessingDiagnostics` and Settings rows for emitted chunks, last chunk duration, queue depth, and dropped frames.
- Captured chunks remain diagnostics-only and are not sent to ASR, translation, subtitles, disk, or LAN services.

## Task 010 — Add simple VAD/chunker

Status: Complete and verified as of 2026-05-20.

Prompt:

```text
Add a simple energy-based VAD and speech chunker. It should suppress silence, mark speech start/end, and flush a segment after configurable silence. Do not integrate real ASR yet; feed chunk events into diagnostics.
```

Acceptance criteria:

- Silence does not produce continuous ASR work.
- Speech activity is visible in diagnostics.
- Settings expose final silence threshold and latency profile.

Implemented notes:

- Added `VoiceActivitySettings` with `VADSensitivity` mappings and backward-compatible settings decode fallback.
- Added `SpeechActivityEvent`, `SpeechSegmentMetadata`, `VoiceActivityDiagnostics`, and `EnergyVoiceActivityDetector`.
- `AudioCaptureService` now keeps continuous `audioChunks` unchanged while exposing separate `speechActivityEvents` and `voiceActivityDiagnostics`.
- `ProcessTapAudioCaptureService` runs VAD in the background preprocessing task after chunk assembly and resets VAD diagnostics on stop.
- Settings shows VAD sensitivity, final silence, speech/VAD counters, current silence, and VAD RMS/peak.
- At Task 010 completion, captured speech activity was diagnostics-only; Task 011 later routes it to local WhisperKit ASR diagnostics.

## Task 011 — Integrate WhisperKit package

Status: Complete and verified as of 2026-05-20.

Prompt:

```text
Add the Argmax OSS Swift package and integrate the WhisperKit product. Implement WhisperKitASRService behind the ASRService protocol. Start with a small/debug model and English source language. The service should accept AudioChunk values and emit TranscriptSegment partial/final events where supported.
```

Acceptance criteria:

- Project builds with WhisperKit dependency.
- Model loads or produces a clear model-download/setup error.
- Real audio can be transcribed in a test path.
- ASR events appear in diagnostics.

Implemented notes:

- Added the `argmax-oss-swift` package at version `1.0.0`, product `WhisperKit`, to the app target.
- Added `WhisperKitASRService` behind `ASRService`, with injectable transcriber support for tests.
- Added local ASR settings and model selection, defaulting to `tiny`.
- Added diagnostics-only routing from VAD speech chunks to local ASR when `Local WhisperKit` is selected.
- Settings shows ASR lifecycle state, backend, model, accepted speech chunks, transcript count, last transcript, and ASR error.
- ASR output is not connected to translation, subtitles, LAN networking, or raw audio persistence yet.

## Task 012 — Wire local ASR to overlay through mock translation

Status: Complete and verified as of 2026-05-21.

Prompt:

```text
Connect Core Audio capture + preprocessing + WhisperKitASRService + MockTranslationService + SubtitleCoordinator + overlay. The overlay should show mock Chinese translations based on real ASR transcript segments.
```

Acceptance criteria:

- Playing English audio causes translated mock subtitle updates.
- ASR transcript text is visible in diagnostics.
- Pipeline can start/stop repeatedly.

Implemented notes:

- Added `LiveSubtitleSessionController` to coordinate supported live subtitle sessions.
- Live subtitle start validates `System Output`, `Local WhisperKit`, and `Mock` translation settings.
- Added `SubtitleCoordinator` external-event mode so live ASR events can be translated/displayed without starting mock ASR.
- Kept `AudioCaptureDiagnosticsModel` as the single `ASRService.events` consumer and added an async ASR event sink for subtitle forwarding.
- Added Start/Stop Live Subtitles controls in Settings and the menu bar.
- ASR final/stable-partial events now update the overlay through `MockTranslationService`; unknown transcripts use the existing mock translation fallback.
- Stop live subtitles stops capture/ASR routing, clears subtitle text, clears the event sink, and leaves the overlay visible.

## Task 013 — Implement Apple Translation backend

Status: Complete and verified as of 2026-05-21.

Prompt:

```text
Implement AppleTranslationService behind TranslationService. Use Apple's Translation framework and LanguageAvailability to check English → Simplified Chinese and English → Traditional Chinese. If unavailable, return a clear error without automatic mock fallback.
```

Acceptance criteria:

- Translation backend compiles and can be selected.
- Availability is checked before translation.
- English transcript segments become Chinese subtitles when available.
- Errors do not crash the pipeline.

Implemented notes:

- Added `AppleTranslationService` behind `TranslationService`.
- Added an injectable Apple translation client seam for tests.
- Mapped English to Simplified Chinese (`zh-Hans`) and Traditional Chinese (`zh-Hant`).
- Used `LanguageAvailability.status(from:to:)` before translation.
- Called `prepareTranslation()` for supported-but-not-installed language pairs.
- Added `TranslationRouterService` for Mock, Apple Translation, and clear Remote LAN not-implemented routing.
- Updated live subtitles to accept Apple Translation and reject Remote LAN translation.
- Added coordinator translation error surfacing without automatic mock fallback.
- Added a post-Task 013 startup fix so the sandboxed app has outbound network, audioanalyticsd/DNS mach lookup exceptions, and read-only access to the networkd preferences file used during model/language-asset setup.
- Live startup now shows visible overlay status/error text before the first subtitle arrives.
- Live ASR now periodically flushes ongoing speech after about 3 seconds so subtitles can update during continuous audio without waiting for VAD final silence.
- First-run WhisperKit and Apple Translation setup may need network access to download/cache model and language assets.

## Task 014 — Add latency metrics

Status: Next task.

Prompt:

```text
Implement MetricsRecorder. Record timestamps for audio capture, chunk emission, ASR partial, ASR final, translation start, translation finish, and overlay render. Show rolling averages in diagnostics and write JSONL logs when diagnostics are enabled.
```

Acceptance criteria:

- Diagnostics show per-stage latency.
- JSONL export includes segment IDs and timestamps.
- Metrics are lightweight and do not block audio callbacks.

## Task 015 — Add remote inference client

Prompt:

```text
Implement RemoteASRService and RemoteTranslationService clients for the WebSocket/HTTP API described in docs/06_INFERENCE_SERVER_SPEC.md. Add settings for server URL, connect/disconnect, and health check. Use mock server responses if no real server exists yet.
```

Acceptance criteria:

- Client can connect to a local test server.
- Binary audio chunks can be sent.
- JSON subtitle events can be received.
- Connection failure is handled gracefully.

## Task 016 — Build LAN inference server skeleton

Prompt:

```text
In a separate server directory, create a Python FastAPI app matching docs/06_INFERENCE_SERVER_SPEC.md. Implement /health, /models, /v1/translate, and a WebSocket /v1/stream endpoint. Use mock ASR and mock translation first.
```

Acceptance criteria:

- Server starts locally.
- Health endpoint works.
- WebSocket accepts session.start and binary audio messages.
- Server emits mock partial/final/subtitle events.

## Task 017 — Integrate faster-whisper on server

Prompt:

```text
Add faster-whisper to the LAN inference server. Implement ASR over buffered PCM chunks. Start with a simple buffered mode, not advanced streaming. Add model selection and GPU configuration via environment variables.
```

Acceptance criteria:

- Server transcribes test audio files.
- Server transcribes streamed chunks with acceptable delay.
- GPU configuration is documented.
- Errors include useful model/CUDA details.

## Task 018 — Integrate server-side translation

Prompt:

```text
Add a CTranslate2 translation backend for English → Simplified Chinese. Start with NLLB or another configured model. Keep TranslationService swappable so an LLM translator can be added later.
```

Acceptance criteria:

- Server translates English strings to Chinese.
- `/v1/translate` works.
- Stream endpoint can emit translated subtitle events.
- Translation latency is recorded.

## Task 019 — Add benchmark mode

Prompt:

```text
Implement benchmark mode as described in docs/07_BENCHMARK_AND_TEST_PLAN.md. It should run a saved audio clip through the selected ASR/translation backend, collect latency metrics, and export a benchmark report.
```

Acceptance criteria:

- User can run benchmark from settings/diagnostics.
- Report includes ASR RTF, translation latency, end-to-end latency, model names, and hardware/backend mode.
- Reports are saved locally.

## Task 020 — Full MVP hardening

Prompt:

```text
Harden the app for real viewing sessions. Handle output-device changes, source app restarts, remote server disconnects, missing permissions, model-load failures, and overlay visibility toggles. Add user-facing error messages and recovery actions.
```

Acceptance criteria:

- App can recover from common errors.
- Start/stop works repeatedly.
- Diagnostics are useful.
- Overlay remains usable across Spaces and app switches where macOS permits.
