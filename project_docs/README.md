# Live Subtitle Translator for macOS

Prepared: 2026-05-20

This documentation pack is intended to help Codex build a realistic Xcode/macOS application that captures Mac audio, transcribes speech, translates it into Chinese subtitles, and renders those subtitles in a movable/resizable always-on-top overlay.

## Product goal

Create a personal macOS app that lets a Chinese-speaking viewer follow English-language streaming video or other Mac audio when Chinese subtitles are unavailable. The app should prioritize readability, privacy, and practical reliability over perfect real-time translation.

## Recommended MVP architecture

```text
macOS app, built in Xcode
  ├─ Core Audio process tap captures system/app audio
  ├─ Audio preprocessor resamples to 16 kHz mono PCM
  ├─ ASR adapter transcribes English speech
  │    ├─ MVP local: WhisperKit / Argmax OSS on the M4 Max
  │    └─ Later LAN: faster-whisper / CTranslate2 on NVIDIA server
  ├─ Translation adapter translates English text to Chinese
  │    ├─ MVP local: Apple Translation Framework, if language pair is available
  │    └─ Later LAN: NLLB / MarianMT / local LLM translator
  └─ AppKit overlay window renders subtitles above other apps
```

## Documents

1. [Requirements](docs/01_REQUIREMENTS.md) — product requirements, scope, non-goals, acceptance criteria.
2. [Technical Context](docs/02_TECH_CONTEXT.md) — current macOS, model, and inference options with source links.
3. [Architecture](docs/03_ARCHITECTURE.md) — app modules, data flow, protocols, and service boundaries.
4. [Implementation Plan](docs/04_IMPLEMENTATION_PLAN.md) — phased build plan from mocked overlay to audio capture to model integration.
5. [Codex Task Backlog](docs/05_CODEX_TASK_BACKLOG.md) — task-by-task prompts and acceptance criteria for Codex.
6. [Inference Server Spec](docs/06_INFERENCE_SERVER_SPEC.md) — optional LAN server API for GPU ASR/translation.
7. [Benchmark and Test Plan](docs/07_BENCHMARK_AND_TEST_PLAN.md) — latency, quality, reliability, and regression tests.
8. [Permissions, Privacy, and Edge Cases](docs/08_PERMISSIONS_PRIVACY_EDGE_CASES.md) — permissions, limitations, DRM/secure UI caveats.
9. [AGENTS.md](AGENTS.md) — repo-level instructions suitable for Codex.

## First build target

Current implementation status: the menu bar app, movable/resizable overlay, mock ASR/translation pipeline skeleton, audio permission/status plumbing, Core Audio tap proof of life, ring buffer/resampler chunk path, simple energy VAD/chunker, local WhisperKit ASR diagnostics, live ASR-to-overlay routing, and Apple Translation behind `TranslationService` are implemented and verified. The app target now declares sandbox entitlements for Core Audio input access, outbound model/language-asset downloads, and the temporary Core Audio analytics mach lookup needed by the current capture path. The next coding phase should add latency metrics and diagnostics display/export.

First-run live E2E can require network access while WhisperKit downloads its selected model from Hugging Face and Apple Translation prepares or downloads language assets. Once those assets are cached by the system/frameworks, later runs may work offline, subject to framework behavior.

Build this first:

```text
Menu bar app
  ↓
Movable/resizable subtitle overlay
  ↓
Mock subtitles
  ↓
Mock ASR -> mock translation pipeline
  ↓
Audio permission/status placeholders
  ↓
Core Audio tap capture proof-of-life waveform/RMS meter
  ↓
Ring buffer + resampler + 16 kHz mono chunks
  ↓
Simple VAD/chunker
  ↓
WhisperKit local ASR
  ↓
Live ASR -> mock translation overlay
  ↓
Apple Translation
  ↓
End-to-end live subtitles
```

Only add the LAN inference server after the local overlay + audio capture path works.

## Important design assumption

For English TV audio → Chinese subtitles, Whisper alone is not enough. Whisper can transcribe English and can translate non-English speech into English, but English → Chinese subtitles require a second translation stage after ASR.
