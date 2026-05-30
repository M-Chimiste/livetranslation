# 02 — Technical Context

Prepared: 2026-05-20

This document summarizes the technical feasibility and major implementation choices for a native macOS live subtitle translator.

## Feasibility summary

The app is feasible as a personal macOS tool. The hardest parts are not raw inference speed; the hard parts are stable audio capture, subtitle segmentation, overlay behavior in full-screen Spaces, and balancing latency against translation quality.

The recommended MVP is:

```text
Core Audio process tap
  → 16 kHz mono PCM ring buffer
  → WhisperKit local ASR
  → Apple Translation or mock/remote translation
  → AppKit subtitle overlay
```

Then add a LAN inference server:

```text
Core Audio process tap on Mac
  → WebSocket to server
  → faster-whisper/CTranslate2 ASR on NVIDIA GPU
  → NLLB/MarianMT/LLM translation
  → subtitle events back to Mac overlay
```

## macOS audio capture options

### Option A — Core Audio process taps

Use this as the primary path.

Apple documents Core Audio taps for capturing system audio, and `AudioHardwareTap` is described as encapsulating an audio tap that can capture outgoing audio from a process or group of processes.

Relevant APIs and concepts:

- `CATapDescription`
- `AudioHardwareCreateProcessTap`
- `AudioHardwareCreateAggregateDevice`
- `AudioDeviceCreateIOProcID`
- `AudioDeviceStart`
- `NSAudioCaptureUsageDescription` in `Info.plist`

Implementation notes:

- Add `NSAudioCaptureUsageDescription` to explain why the app captures system audio.
- Create a process tap for the selected process or a system-level tap if supported by the chosen implementation.
- Attach the tap to a private aggregate device.
- Consume buffers in an IOProc callback.
- Copy only what is needed into a ring buffer and return quickly.
- Do not run ASR, translation, or SwiftUI updates inside the Core Audio callback.

Reference implementation to study:

- Apple sample: https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps
- `NSAudioCaptureUsageDescription`: https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription
- `AudioHardwareTap`: https://developer.apple.com/documentation/coreaudio/audiohardwaretap
- AudioCap sample: https://github.com/insidegui/AudioCap

### Option B — ScreenCaptureKit audio capture

Use this only as a fallback.

ScreenCaptureKit supports high-performance screen and audio capture. The issue is that the API is conceptually tied to screen/window/app capture, and may involve Screen Recording permissions even when the app only needs audio.

Reference:

- ScreenCaptureKit overview: https://developer.apple.com/documentation/screencapturekit/
- ScreenCaptureKit `capturesAudio`: https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio

### Option C — virtual audio device

Avoid for the MVP.

Tools like BlackHole, Loopback, or Soundflower-style routing can work, but they make installation and support more complicated. The goal is a native app without driver installation.

## Overlay rendering

Use AppKit, even if the rest of the app is SwiftUI.

Recommended approach:

- Create an `NSPanel` or borderless `NSWindow`.
- Make it transparent and non-opaque.
- Use an `NSHostingView` to host SwiftUI subtitle views.
- Set a high but reasonable window level, initially `.statusBar` or `.floating` depending on behavior.
- Set collection behavior to join Spaces and support full-screen auxiliary display.
- Toggle `ignoresMouseEvents` when locked.
- In edit mode, allow drag and resize.

Relevant AppKit concepts:

- `NSWindow.Level` controls stacking levels.
- `NSWindow.CollectionBehavior` controls behavior across Spaces and full-screen contexts.
- `.canJoinAllSpaces` allows windows to appear in all Spaces.
- `.fullScreenAuxiliary` helps auxiliary windows appear with full-screen apps.

References:

- `NSWindow.Level`: https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct
- `NSWindow.CollectionBehavior`: https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct
- `.canJoinAllSpaces`: https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces
- `.fullScreenAuxiliary`: https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary
- `NSPanel`: https://developer.apple.com/documentation/AppKit/NSPanel

Caveat: macOS does not guarantee that a third-party overlay can appear above every secure or protected UI surface. The app should describe this honestly in settings/help text.

## ASR options

### Option A — WhisperKit / Argmax OSS in the Mac app

Recommended first real ASR backend.

Argmax OSS is a Swift package that includes WhisperKit for speech-to-text with OpenAI Whisper. The package can be added from `https://github.com/argmaxinc/argmax-oss-swift`, and the README documents selecting the `WhisperKit` product. It also includes CLI/server options and OpenAI Audio API compatibility for some workflows.

Why it fits:

- Native Swift package.
- Designed for Apple Silicon.
- Good Xcode integration path.
- Keeps the first MVP on the Mac without a server.

Risks:

- Real-time streaming behavior may require adapting the audio pipeline to WhisperKit’s preferred inputs.
- Model downloads and Core ML model management need clear UX.
- Local ASR speed should be benchmarked on the M4 Max with the chosen model.

Reference:

- Argmax OSS / WhisperKit: https://github.com/argmaxinc/argmax-oss-swift

### Option B — whisper.cpp

Good fallback or alternative.

`whisper.cpp` is a C/C++ implementation of Whisper with Apple Silicon optimizations including ARM NEON, Accelerate, Metal, and Core ML. It also supports CUDA for NVIDIA GPUs.

Why it fits:

- Mature local Whisper implementation.
- Cross-platform.
- Can be embedded or served separately.
- Supports quantized models.

Risks:

- More manual integration into a Swift app.
- Streaming and partials need careful implementation.

Reference:

- whisper.cpp: https://github.com/ggml-org/whisper.cpp

### Option C — faster-whisper + CTranslate2 server

Recommended LAN server backend after the MVP.

`faster-whisper` is a CTranslate2 reimplementation of Whisper. Its README reports up to 4x faster inference than OpenAI Whisper for the same accuracy and lower memory use, with further efficiency gains from 8-bit quantization. It supports GPU execution with CUDA/cuBLAS/cuDNN.

Why it fits:

- Very strong match for the RTX GPUs.
- Easy to wrap in Python FastAPI/WebSocket.
- Keeps the Mac app lightweight.
- Server can be upgraded independently.

Risks:

- LAN network and server lifecycle complexity.
- Need a custom streaming/chunking policy.
- Need careful GPU/CUDA dependency management.

References:

- faster-whisper: https://github.com/SYSTRAN/faster-whisper
- CTranslate2: https://github.com/OpenNMT/CTranslate2

## Translation options

### Option A — Apple Translation Framework

Recommended first translation backend if English → Chinese is available on the user’s macOS.

Apple’s Translation framework provides in-app translation, and `LanguageAvailability` can check whether a language or language pair is supported and installed.

Why it fits:

- Native.
- Local/system-integrated behavior.
- No separate server needed.

Risks:

- Availability varies by OS/language pair.
- API ergonomics may require SwiftUI integration patterns.
- Less control than a custom translation model.

References:

- Translation framework: https://developer.apple.com/documentation/translation/
- Translating text within your app: https://developer.apple.com/documentation/Translation/translating-text-within-your-app
- `LanguageAvailability`: https://developer.apple.com/documentation/translation/languageavailability

### Option B — NLLB via CTranslate2

Recommended deterministic LAN translation backend.

NLLB-200 is a Meta translation model family designed to translate across 200 languages. CTranslate2 supports NLLB, MarianMT, M2M100, Whisper, and other Transformer models after conversion.

Why it fits:

- Strong open-source translation option.
- Works well as a server-side model.
- CTranslate2 can optimize inference on CPU/GPU.

Risks:

- NLLB may be less idiomatic than a modern LLM for subtitle-style Chinese.
- Needs careful language codes, tokenizer handling, and sentence segmentation.

References:

- Meta NLLB-200: https://ai.meta.com/blog/nllb-200-high-quality-machine-translation/
- CTranslate2 Transformers support: https://opennmt.net/CTranslate2/guides/transformers.html
- NLLB with CTranslate2 tutorial: https://forum.opennmt.net/t/nllb-200-with-ctranslate2/5090

### Option C — local LLM translator

Recommended as a later quality upgrade.

A local instruction model can translate short ASR segments into more natural Chinese subtitles. It can also compress overly literal output into subtitle-friendly wording.

Why it fits:

- Better control over style.
- Can preserve context across recent segments.
- Can produce more natural Chinese than pure MT for dialogue.

Risks:

- More latency than classic MT.
- More possibility of paraphrase or hallucination.
- Needs prompt discipline and maybe post-processing.

Good prompt pattern:

```text
Translate the English subtitle into concise Simplified Chinese.
Preserve meaning. Do not add explanations.
Use natural spoken Chinese. Keep it short enough for subtitles.
Previous context: {previous_2_segments}
Subtitle: {current_segment}
```

## Important Whisper limitation

Whisper is not an English → Chinese speech translation solution by itself. OpenAI’s Whisper documentation describes transcription and translation of non-English speech into English. For this app, English TV audio should be transcribed to English first, then translated to Chinese by a separate translation backend.

Reference:

- OpenAI Whisper README: https://github.com/openai/whisper

## Recommended initial technology choices

For the first usable MVP:

| Area | Recommended choice | Reason |
|---|---|---|
| App | Xcode macOS app | User requested Xcode, native overlay and permissions are easier. |
| UI | SwiftUI + AppKit | SwiftUI for settings, AppKit for overlay window. |
| Audio | Core Audio process taps | Audio-only, no virtual driver, better fit than screen capture. |
| ASR | WhisperKit / Argmax OSS | Native Swift package, Apple Silicon-oriented. |
| Translation | Apple Translation or mock first | Fastest path to integrated local translation. |
| Overlay | AppKit `NSPanel`/`NSWindow` | Best control for always-on-top subtitle behavior. |
| Remote later | faster-whisper + CTranslate2 | Strong match for NVIDIA GPUs and LAN server. |

## Risk register

| Risk | Probability | Impact | Mitigation |
|---|---:|---:|---|
| Core Audio tap setup is finicky | Medium | High | Start with AudioCap-style proof-of-life, add diagnostics. |
| Apple Translation does not support desired pair or API flow | Medium | Medium | Keep `TranslationService` protocol and remote/mock fallback. |
| Overlay does not appear over some full-screen apps | Medium | Medium | Use AppKit collection behavior, document limitations. |
| Subtitles flicker due to partial ASR rewrites | High | Medium | Add stabilizer; render final or stable partials only. |
| Translation poor on incomplete fragments | High | High | Segment on punctuation/silence; keep short recent context. |
| LAN server adds complexity | Medium | Medium | Build local MVP first; server is optional adapter. |
| Notifications get transcribed | Medium | Low | Prefer per-process capture; add app exclusion list. |

