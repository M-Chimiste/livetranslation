# AGENTS.md — Codex Instructions

## Project mission

Build a native macOS application in Xcode that captures local Mac audio, transcribes it, translates it to Chinese, and displays readable subtitles in a movable/resizable overlay above other apps.

## Current handoff

Phase 0, Phase 1, Phase 2, Phase 3, Phase 4, Phase 5 / Task 009, Phase 6 / Task 010, Phase 7 / Task 011, Phase 8 / Task 012, and Phase 9 / Task 013 are complete: the app is a menu bar agent with settings, persisted placeholder configuration, a transparent AppKit subtitle overlay, lock/unlock behavior, move/resize edit mode, persisted overlay frame/lock state, protocol-backed mock/test scaffolding, audio capture permission/status plumbing, a Core Audio system-output capture proof of life, diagnostics-only continuous 16 kHz mono Float32 audio chunk emission, energy-based speech activity events, local WhisperKit ASR diagnostics, live ASR-to-overlay subtitle routing, and selectable mock or Apple Translation. The app target has sandbox entitlements for Core Audio input access and outbound network access plus runtime exceptions for `com.apple.audioanalyticsd`, `com.apple.dnssd.service`, and read-only access to `/Library/Preferences/com.apple.networkd.plist` needed by current audio/network model setup paths.

First-run live E2E may need internet access to download/cache the selected WhisperKit model and Apple Translation language assets. If live startup fails before subtitles arrive, the overlay now shows a short non-subtitle status/error while Settings keeps the detailed diagnostic error. Once live audio activity is detected, the listening hint clears and the overlay stays blank until an actual translated subtitle or error arrives. Mock pipeline controls are no longer exposed in the menu bar or Settings UI.

The next implementation pass should add latency metrics and diagnostics display/export. Keep LAN networking and raw audio persistence out of that pass unless the task plan explicitly expands scope.

## Development principles

- Prefer Swift + SwiftUI for app state and settings.
- Prefer AppKit for the overlay window, because subtitle overlays need precise control over window levels, input behavior, Spaces, and full-screen behavior.
- Prefer Core Audio process taps for audio-only capture.
- Use ScreenCaptureKit only as a fallback, because this product does not need video capture.
- Keep ASR and translation behind protocols so the app can switch between local Mac inference and LAN inference.
- Start with mock ASR/translation services before integrating real models.
- Do not build any DRM circumvention, protected-video capture, or content extraction feature. The app should capture audio only for live personal accessibility/context.
- Do not depend on cloud APIs for the default path. The app should work locally or on the user's local network.
- Treat latency and stability as first-class: log timestamps at capture, ASR partial, ASR final, translation final, and render.

## Suggested repo structure

```text
LiveSubtitleTranslator/
  LiveSubtitleTranslator.xcodeproj
  LiveSubtitleTranslator/
    App/
      LiveSubtitleTranslatorApp.swift
      AppDelegate.swift
      MenuBarController.swift
    Overlay/
      SubtitleOverlayWindowController.swift
      SubtitleOverlayView.swift
      OverlayEditView.swift
    AudioCapture/
      AudioCaptureService.swift
      ProcessTapAudioCaptureService.swift
      MockAudioCaptureService.swift
      AudioRingBuffer.swift
      AudioResampler.swift
    Speech/
      ASRService.swift
      WhisperKitASRService.swift
      RemoteASRService.swift
      MockASRService.swift
    Translation/
      TranslationService.swift
      AppleTranslationService.swift
      RemoteTranslationService.swift
      MockTranslationService.swift
    Subtitles/
      SubtitleCoordinator.swift
      SubtitleModels.swift
      SubtitleStabilizer.swift
    Settings/
      AppSettings.swift
      SettingsStore.swift
      SettingsView.swift
    Diagnostics/
      MetricsRecorder.swift
      DiagnosticOverlayView.swift
  Tests/
    SubtitleStabilizerTests.swift
    SettingsStoreTests.swift
    MockPipelineTests.swift
  docs/
```

## Implementation order

1. Create the menu bar app shell with settings and module folders. Complete.
2. Build the AppKit subtitle overlay MVP with mock Chinese subtitles. Complete.
3. Add pipeline protocols, core data models, mock ASR, and mock translation. Complete.
4. Wire mock ASR -> mock translation -> subtitle overlay through `SubtitleCoordinator`. Complete.
5. Add audio permission plumbing and diagnostics placeholders. Complete.
6. Add Core Audio process tap proof of life with RMS/peak diagnostics. Complete.
7. Add ring buffer, resampler, and 16 kHz mono chunking. Complete.
8. Add simple energy VAD/chunker. Complete.
9. Integrate local ASR, preferably WhisperKit / Argmax OSS. Complete.
10. Wire local ASR to mock translation and overlay. Complete.
11. Add Apple Translation or an explicitly selected fallback. Complete.
12. Add latency metrics and diagnostics display/export. Next.
13. Add optional LAN inference only after local overlay + capture paths work.
14. Add benchmark mode and end-to-end latency metrics.

## Coding standards

- Use Swift concurrency where practical, but do not block Core Audio callbacks.
- Do not allocate heavily or perform model inference inside audio callbacks.
- Audio callbacks should write to a ring buffer or async-safe queue and return quickly.
- Use dependency injection so tests can run with mock services.
- Keep UI updates on the main actor.
- Favor small services with clear protocols over monolithic view models.

## Definition of done for MVP

- User can start/stop subtitle mode from the menu bar.
- App captures audio from a selected app or system output.
- App renders Chinese subtitle lines in an overlay above ordinary apps.
- User can move and resize the overlay, then lock it.
- App persists overlay position, size, target language, and backend choice.
- End-to-end latency is logged and visible in diagnostics.
- The app can run without sending audio to the public internet.
