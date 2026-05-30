# AGENTS.md

## Project Mission

Build a native macOS app that captures audio playing on the Mac, transcribes English speech, translates it into Chinese, and renders readable subtitles in a movable, resizable, always-on-top overlay.

The first real use case is personal viewing of English-language video when Chinese subtitles are unavailable. Optimize for readability, privacy, reliability, and practical latency over perfect real-time captioning.

## Current Repo State

This repository is currently a native macOS menu bar app with the Phase 1 subtitle overlay MVP, Phase 2 mock pipeline skeleton, Phase 3 audio permission/status plumbing, Phase 4 Core Audio capture proof of life, Phase 5 audio preprocessing chunks, Phase 6 simple energy VAD/chunker, Phase 7 local WhisperKit ASR diagnostics, Phase 8 live ASR to overlay routing, Phase 9 Apple Translation backend, and post-Task 013 live E2E startup/capture-lifecycle fixes implemented:

- App target: `LiveSubtitleTranslator`
- Tests: `LiveSubtitleTranslatorTests` using Swift Testing
- UI tests: `LiveSubtitleTranslatorUITests` using XCTest
- Current app code uses a SwiftUI `MenuBarExtra` app shell with a SwiftUI Settings scene.
- The stock SwiftUI + SwiftData starter (`WindowGroup`, `ContentView`, `Item`) has been removed.
- The app has an AppKit transparent subtitle overlay panel hosting SwiftUI content.
- A mock ASR -> coordinator -> mock translation pipeline remains available as test/development scaffolding, but visible app controls now focus on live subtitles.
- The Phase 1 mock Chinese subtitle ticker remains available as a utility/test artifact.
- Overlay visibility, lock/unlock, reset, drag/resize edit mode, and persisted frame/lock state are implemented.
- Live startup can show non-subtitle overlay status/error text before the first translated subtitle arrives.
- Core service protocols, deterministic mock ASR/translation services, subtitle stabilization/wrapping utilities, and in-memory metrics recording are implemented.
- Generated Info.plist settings include the system audio capture usage description.
- The app remains sandboxed and declares Core Audio input access, outbound client networking, mach lookup exceptions for `com.apple.audioanalyticsd` and `com.apple.dnssd.service`, and read-only access to `/Library/Preferences/com.apple.networkd.plist` for the current capture/model setup paths.
- Audio Capture permission is checked/requested with the TCC-backed system audio recording provider used by Core Audio process taps. Denied users are pointed to System Settings privacy recovery.
- Settings can refresh audio sources, start/stop system-output capture, and show permission, capture state, source count, last error, RMS, peak, Core Audio callback/captured-frame counters, emitted chunk count, last chunk duration, queue depth, dropped frames, VAD diagnostics, ASR diagnostics, and live pipeline forwarding/translation diagnostics.
- `ProcessTapAudioCaptureService` creates a private Core Audio process tap and aggregate device for system-output proof of life, writes callback samples into `AudioRingBuffer`, emits diagnostics-only continuous 16 kHz mono Float32 `AudioChunk` values through a background preprocessing task, and emits separate speech activity/VAD diagnostics.
- `WhisperKitASRService` is implemented behind `ASRService`; the live path routes continuous 16 kHz mono chunks to WhisperKit, while VAD remains visible as diagnostics and can trigger early flushes.
- `AppleTranslationService` is implemented behind `TranslationService`; Remote LAN translation is still not implemented.
- First-run live E2E may require internet access so WhisperKit can download/cache the selected model and Apple Translation can prepare/download language assets.
- Generated Info.plist settings are currently managed through the Xcode project (`GENERATE_INFOPLIST_FILE = YES`).
- Main project documentation lives under `project_docs/`.

Treat `project_docs/project_status.md` as the current implementation handoff, and treat the rest of `project_docs/` as the product and architecture source of truth.

## Read These Before Coding

Start with:

1. `project_docs/README.md`
2. `project_docs/docs/01_REQUIREMENTS.md`
3. `project_docs/docs/03_ARCHITECTURE.md`
4. `project_docs/docs/04_IMPLEMENTATION_PLAN.md`
5. `project_docs/docs/05_CODEX_TASK_BACKLOG.md`

Read these when touching their areas:

- Audio, models, and translation choices: `project_docs/docs/02_TECH_CONTEXT.md`
- LAN server/client protocol: `project_docs/docs/06_INFERENCE_SERVER_SPEC.md`
- Latency, benchmarks, and regression tests: `project_docs/docs/07_BENCHMARK_AND_TEST_PLAN.md`
- Permissions, privacy, DRM boundaries, and edge cases: `project_docs/docs/08_PERMISSIONS_PRIVACY_EDGE_CASES.md`

There is also a seed instruction file at `project_docs/AGENTS.md`; this root file is the active repo-level guide.

## Implementation Order

Build in small, working phases. Do not try to implement the full product in one pass.

1. Replace the stock starter app with the real app shell: menu bar entry, settings, and module folders. Complete.
2. Build the subtitle overlay MVP with mock Chinese subtitles. Complete.
3. Add pipeline protocols and mock ASR/translation. Complete.
4. Wire mock ASR -> mock translation -> subtitle overlay through `SubtitleCoordinator`. Complete.
5. Add audio permission plumbing and diagnostics placeholders. Complete.
6. Add Core Audio process tap proof of life with RMS/peak diagnostics. Complete.
7. Add ring buffer, resampler, and 16 kHz mono chunking. Complete.
8. Add simple energy VAD/chunker. Complete.
9. Integrate local ASR, preferably WhisperKit / Argmax OSS. Complete.
10. Wire local ASR to mock translation and overlay. Complete.
11. Add Apple Translation or an explicitly selected fallback. Complete.
12. Fix live E2E startup, capture lifecycle, permission recovery, and primary live-subtitle UI. Complete.
13. Add latency metrics and diagnostics display/export. Next.
14. Add optional LAN inference only after local overlay + capture paths work.

## Architecture Principles

- Use Swift and SwiftUI for app state, settings, and ordinary UI.
- Use AppKit for the subtitle overlay window because it needs precise control of window level, Spaces behavior, mouse-event passthrough, dragging, and resizing.
- Keep audio capture, preprocessing, ASR, translation, subtitle stabilization, overlay rendering, settings, and diagnostics in separate modules.
- Put ASR behind `ASRService` and translation behind `TranslationService`.
- Provide mock services first so UI and coordinator work can proceed without audio permissions, models, or a server.
- Keep UI updates on the main actor.
- Use dependency injection so tests can exercise the pipeline with mocks.
- Prefer small services with clear protocols over large view models.

## Audio Rules

Use Core Audio process taps as the primary capture path. ScreenCaptureKit is only a fallback, and virtual audio drivers are out of scope for the MVP.

Core Audio callbacks must stay minimal:

- Validate format.
- Copy only what is needed into a ring buffer or async-safe queue.
- Return quickly.

Do not allocate heavily, run inference, call SwiftUI/AppKit, perform chatty logging, or `await` inside audio callbacks.

Captured audio should become timestamped 16 kHz mono Float32 chunks before ASR. Use `AVAudioConverter` for resampling and mixdown where practical. In the current live path, continuous chunks feed WhisperKit; VAD is a diagnostics and early-flush signal, not the primary audio filter.

## Overlay Rules

The overlay should be a transparent AppKit `NSPanel` or borderless `NSWindow` hosting SwiftUI content with `NSHostingView`.

Expected behavior:

- Movable and resizable in edit mode.
- Click-through when locked.
- Visible above ordinary apps and many full-screen Spaces where macOS permits.
- Honest about limitations in secure or protected UI contexts.
- Readable Chinese subtitles, normally one or two lines, with controlled wrapping.

Keep mock subtitle and status-display paths available for tests and recovery states, but treat live subtitles as the primary user flow.

## Privacy and Product Boundaries

- Default to on-device or local-network processing.
- Do not require or introduce public cloud APIs for the default path.
- Do not store raw audio by default.
- Keep logs local and make diagnostics logging user-controlled.
- Do not request microphone permission for the MVP.
- The current Core Audio process tap path declares Core Audio input access because the tap is exposed as an aggregate-device input stream; do not add microphone capture or read microphone samples.
- Do not request Screen Recording permission unless implementing a ScreenCaptureKit fallback.
- Do not request Accessibility permission unless adding a feature that truly needs it.
- Do not build DRM circumvention, protected-video capture, OCR subtitle extraction, or streaming-service content extraction.
- If protected content cannot be captured, fail gracefully and explain the limitation.

## Settings and Diagnostics

Persist:

- Overlay frame and style.
- Target language: Simplified Chinese first, Traditional Chinese later.
- ASR backend.
- Translation backend.
- Remote server URL, if used.
- Latency profile.
- Diagnostics preference.
- Voice activity sensitivity and final silence.

Diagnostics should make failures and latency visible:

- Audio RMS/input levels.
- Capture, chunk, ASR, translation, and render timestamps.
- End-to-end latency.
- Backend and model names.
- Optional JSONL logs when diagnostics are enabled.

Do not write raw audio or full transcripts unless the user explicitly enables a diagnostic mode for that.

## Testing Guidance

Use focused tests as modules appear:

- Subtitle wrapping.
- Duplicate suppression.
- Stable partial handling.
- Settings persistence.
- Translation context windows.
- Remote message encoding/decoding.
- Audio chunk timing math.

Keep model, audio-permission, and LAN-server work testable through mocks. UI tests can stay light until there is stable UI surface worth automating.

## Build and Test Commands

Useful local commands:

```bash
xcodebuild -project LiveSubtitleTranslator.xcodeproj -scheme LiveSubtitleTranslator -destination 'platform=macOS' build
xcodebuild -project LiveSubtitleTranslator.xcodeproj -scheme LiveSubtitleTranslator -destination 'platform=macOS' test
```

If signing or destination selection becomes noisy in automation, keep the project compiling in Xcode and document the exact failure in the handoff.

## Repository Hygiene

- Keep local OS, editor, Xcode, SwiftPM cache, build, and test-result artifacts out of Git. `.gitignore` should cover `.DS_Store`, `build/`, `DerivedData/`, `*.xcresult`, `*.xcactivitylog`, `*.xcuserstate`, `.build/`, and `.swiftpm/`.
- Keep source, tests, docs, the Xcode project, entitlements, and intentional SwiftPM pins trackable. Do not ignore `LiveSubtitleTranslator.xcodeproj`, `project_docs/`, `LiveSubtitleTranslator.entitlements`, or Xcode SwiftPM `Package.resolved` files.
- When adding diagnostics exports or cache directories, use a narrow ignore rule for the generated local-output path instead of broad source-like patterns.

## Sensitive Data and Sharing

- Do not commit API keys, bearer tokens, shared secrets, passwords, private keys, signing certificates, provisioning profiles, service-account JSON, or vendor service plists.
- Keep shared Xcode project signing metadata account-neutral. In particular, do not commit a personal `DEVELOPMENT_TEAM`; leave it blank in `project.pbxproj` and choose a local team in Xcode only for local builds.
- If a feature needs local credentials or machine-specific build settings, store them in ignored files such as `.env`, `*.local.xcconfig`, `Secrets*.xcconfig`, or `LocalSecrets*.plist`, and commit only placeholder/sample files such as `.env.example`.
- Before sharing the source, run a quick secret scan over tracked files and inspect any hits in `LiveSubtitleTranslator.xcodeproj/project.pbxproj`, entitlements, plist files, Swift source, and docs.

## Coding Style

- Follow existing Swift project conventions as they emerge.
- Prefer Swift concurrency for pipeline orchestration, but keep real-time audio callbacks synchronous and tiny.
- Avoid global singletons for services that need mocks in tests.
- Use clear names matching the docs: `AudioCaptureService`, `ASRService`, `TranslationService`, `SubtitleCoordinator`, `SubtitleDisplayState`, `MetricsRecorder`.
- Add comments only where they explain non-obvious behavior, especially Core Audio lifecycle and threading constraints.
- Keep changes scoped to the current milestone or task.

## Immediate Next Task

The implementation has completed Task 001, Task 002, Task 003, Task 004, Task 005, Task 007, Task 008, Task 009, Task 010, Task 011, Task 012, and Task 013 from `project_docs/docs/05_CODEX_TASK_BACKLOG.md`, plus post-Task 013 live E2E startup, capture-lifecycle, and live-UI cleanup fixes. Task 006 is partially complete for the line wrapping utility and tests; configurable overlay style settings remain future work.

The next coding pass should begin Task 014: add latency metrics and diagnostics display/export. Keep LAN networking, raw audio persistence, and model benchmarking out of that pass unless a new plan explicitly expands scope.
