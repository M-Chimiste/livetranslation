# Live Subtitle Translator

A native macOS menu-bar app that captures the audio playing on your Mac, transcribes English speech on-device, translates it to Chinese, and renders readable subtitles in a movable, always-on-top overlay.

The first use case is personal viewing of English-language video when Chinese subtitles aren't available. It optimizes for readability, privacy, reliability, and *practical* latency over perfect real-time captioning.

> **Privacy first.** All processing runs on-device (or, eventually, on your LAN). There are no public cloud APIs in the default path, raw audio is never persisted by default, and the app captures **system audio only** — no microphone, no screen recording, no protected-content capture.

## Status

The local end-to-end pipeline is working. The app can run:

```
Core Audio system-output tap → 16 kHz mono chunks → WhisperKit ASR → Apple Translation → subtitle overlay
```

Phases 0–9 are implemented and verified (app shell, overlay MVP, mock pipeline, audio permission plumbing, Core Audio capture, preprocessing/chunking, energy VAD, local WhisperKit ASR, live ASR→overlay routing, Apple Translation backend), plus live end-to-end startup, capture-lifecycle, and permission-recovery fixes.

**Next up:** latency metrics and a diagnostics display/export panel. **Not yet implemented:** configurable overlay styling, the LAN inference client/server, and persisted/exported latency metrics.

Authoritative status lives in [`AGENTS.md`](AGENTS.md) and [`project_docs/project_status.md`](project_docs/project_status.md).

## Features

- **System-audio capture** via Core Audio process taps (`CATapDescription` + private aggregate device) — follows whatever is playing on your default output device, no microphone access.
- **On-device English ASR** with [WhisperKit](https://github.com/argmaxinc/WhisperKit) (`argmax-oss-swift`), selectable model (`tiny` by default, `large-v3` available).
- **English → Chinese translation** via Apple's on-device Translation framework, Simplified (`zh-Hans`) or Traditional (`zh-Hant`). A mock backend is also selectable for development.
- **Transparent AppKit overlay** that is movable/resizable in edit mode, click-through when locked, and stays above ordinary apps and many full-screen Spaces. Frame and lock state persist across launches.
- **Diagnostics in Settings** — permission/capture state, RMS/peak levels, Core Audio callback and frame counters, chunk-flow stats, VAD/speech-activity state, ASR lifecycle, and live forwarding/translation counters.
- **Energy-based VAD** used as a diagnostics and early-flush signal (the live ASR path receives continuous chunks, not VAD-gated audio).
- **Mock-first architecture** so the UI and coordinator can be developed and tested without audio permission, models, or downloads.

## Requirements

- macOS **26.5** or later (deployment target).
- Xcode with the matching macOS SDK.
- Apple Developer signing for local runs. The shared project leaves `DEVELOPMENT_TEAM` blank; select your own team in Xcode if required.
- **Internet on first live run** so WhisperKit can download/cache the selected model and Apple Translation can prepare language assets. Capture and translation are on-device after that.
- When you first start capture, macOS prompts for **System Audio Recording** permission (System Settings → Privacy & Security → Screen & System Audio Recording → *System Audio Recording Only*).

## Build, test, run

The project is `LiveSubtitleTranslator.xcodeproj`. For day-to-day work, open it in Xcode and use **Cmd-B** / **Cmd-U**.

```bash
# Build (Debug)
xcodebuild -project LiveSubtitleTranslator.xcodeproj \
  -scheme LiveSubtitleTranslator -configuration Debug build

# Run all unit + UI tests
xcodebuild -project LiveSubtitleTranslator.xcodeproj \
  -scheme LiveSubtitleTranslator -destination 'platform=macOS' test

# Run a single Swift Testing test
xcodebuild -project LiveSubtitleTranslator.xcodeproj \
  -scheme LiveSubtitleTranslator -destination 'platform=macOS' test \
  -only-testing:LiveSubtitleTranslatorTests/LiveSubtitleTranslatorTests/appSettingsDefaultsAreDeterministic
```

Unit tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) and live in a single `LiveSubtitleTranslatorTests` struct. UI tests use XCTest. The current suite is 77 unit tests + 1 UI launch smoke test.

The app is a menu-bar agent (`LSUIElement = YES`) — there's no Dock icon. After launching, look for the **Live Subtitle Translator** item in the menu bar; open **Settings** from there to pick sources/backends and **Start Live Subtitles**.

### Using it

1. Open **Settings** from the menu-bar item.
2. Set **Audio Source** = `System Output`, **ASR Backend** = `Local WhisperKit`, **Translation Backend** = `Apple Translation` (or `Mock`).
3. **Start Live Subtitles.** Grant the System Audio Recording prompt if asked.
4. Play English audio. The overlay shows status text first, then translated Chinese subtitles. Use **Lock/Unlock** for click-through and **Reset Overlay Position** if it drifts off-screen.

## Architecture

The pipeline:

```
Core Audio process tap  →  AudioRingBuffer  →  AudioResampler (16 kHz mono Float32)
  →  AudioChunkAssembler + energy VAD (SpeechActivityEvent)
  →  ASRService (WhisperKitASRService / MockASRService)
  →  SubtitleCoordinator + SubtitleStabilizer
  →  TranslationRouterService → (AppleTranslationService | MockTranslationService)
  →  SubtitleDisplayModel  →  AppKit NSPanel (SubtitleOverlayWindowController)
```

The composition root is [`AppState`](LiveSubtitleTranslator/App/AppState.swift). The `@main` entry [`LiveSubtitleTranslatorApp`](LiveSubtitleTranslator/App/LiveSubtitleTranslatorApp.swift) is a SwiftUI `MenuBarExtra` + `Settings` scene that owns one `AppState`. Every service is constructor-injected so tests can substitute fakes. `TranslationRouterService` picks the translation backend from settings at translate time.

### Module layout

| Module | Responsibility |
| --- | --- |
| `App/` | App shell, `AppState`, menu-bar content, `LiveSubtitleSessionController`, mock pipeline scaffolding |
| `AudioCapture/` | `AudioCaptureService` protocol, `ProcessTapAudioCaptureService`, ring buffer, resampler, chunk assembler, VAD |
| `Speech/` | `ASRService` protocol, `WhisperKitASRService`, `MockASRService` |
| `Translation/` | `TranslationService` protocol, `AppleTranslationService`, `MockTranslationService`, `TranslationRouterService` |
| `Subtitles/` | `SubtitleCoordinator`, `SubtitleStabilizer`, `SubtitleLineWrapper`, display model/state, mock ticker |
| `Overlay/` | `SubtitleOverlayWindowController` (NSPanel) + `SubtitleOverlayView` (SwiftUI via `NSHostingView`) |
| `Settings/` | `AppSettings`, `SettingsStore` (UserDefaults), `SettingsView` |
| `Diagnostics/` | `MetricsRecorder`, `AudioCaptureDiagnosticsModel`, `ASRDiagnostics` |

### Key design decisions

- **AppKit for the overlay, SwiftUI for everything else.** The overlay needs precise control over window level, Spaces collection behavior, full-screen aux behavior, and mouse-event passthrough — things SwiftUI windows can't express. Menu bar and Settings stay in SwiftUI.
- **Core Audio process taps are the primary capture path.** ScreenCaptureKit is a fallback only, since it would force a Screen Recording permission for an audio-only feature. Virtual audio drivers are out of scope.
- **The IOProc callback stays trivial:** validate format, copy samples into the ring buffer, return. No allocations, inference, UI calls, `await`, or per-buffer logging — all heavy work happens off the callback thread by draining the ring buffer.
- **Translation is a separate stage from ASR.** Whisper transcribes English; English → Chinese is a second pass (Apple Translation today, LAN remote planned).
- **Partial transcripts churn,** so `SubtitleStabilizer` translates on finals/stable partials and keeps the previous subtitle visible until the next is ready.

## Privacy & boundaries

- Default to on-device or local-network processing; no public cloud APIs in the default path.
- System audio only — no microphone, Screen Recording, or Accessibility permissions for the MVP.
- No raw audio or full transcripts stored by default (only behind an explicit diagnostics toggle).
- No DRM circumvention, protected-video capture, OCR subtitle extraction, or streaming-service content extraction. If protected content can't be captured, the app fails gracefully and explains the limitation.

The app is sandboxed with a narrow entitlements set (audio input, network client, and specific mach-lookup / read-only-path exceptions that Core Audio and Apple Translation need). See [`LiveSubtitleTranslator.entitlements`](LiveSubtitleTranslator/LiveSubtitleTranslator.entitlements).

## Documentation

- [`AGENTS.md`](AGENTS.md) — active repo-level guide and next-task source.
- [`CLAUDE.md`](CLAUDE.md) — guidance for Claude Code working in this repo.
- [`project_docs/project_status.md`](project_docs/project_status.md) — current implementation handoff.
- [`project_docs/docs/`](project_docs/docs/) — product & architecture source of truth:
  - `01_REQUIREMENTS.md`, `02_TECH_CONTEXT.md`, `03_ARCHITECTURE.md`
  - `04_IMPLEMENTATION_PLAN.md`, `05_CODEX_TASK_BACKLOG.md`
  - `06_INFERENCE_SERVER_SPEC.md`, `07_BENCHMARK_AND_TEST_PLAN.md`, `08_PERMISSIONS_PRIVACY_EDGE_CASES.md`

Read `03_ARCHITECTURE.md` before non-trivial pipeline changes. Build in small, working phases — don't expand scope past the active task without an explicit plan update.
