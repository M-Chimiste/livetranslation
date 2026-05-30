# 01 — Requirements

Prepared: 2026-05-20

## Objective

Create a native macOS app that captures audio playing on the Mac, transcribes spoken dialogue, translates it into Chinese, and displays readable subtitles in an overlay that can appear above other applications.

The first target use case is watching English-language streaming TV with a Chinese-speaking viewer when official Chinese subtitles are unavailable.

## Primary user story

> As a user watching TV or video on my Mac, I want live Chinese subtitles generated from the program audio so that my wife can follow the context even when the stream has no Chinese subtitle track.

## Success criteria

The MVP is successful when:

- The app can capture audio from the Mac without installing a virtual audio driver.
- The app displays readable Chinese subtitles over a playing video app/browser.
- The subtitle overlay can be moved and resized manually.
- The overlay can be locked so it does not intercept normal playback clicks.
- The app can run locally on the M4 Max or on a local-network inference server.
- Typical subtitle latency is acceptable for casual TV viewing.
- The app does not require a public cloud API.

## Target environment

User-provided hardware:

- MacBook Pro with M4 Max and 128 GB unified memory.
- Two RTX 6000 Blackwell GPUs.
- One RTX 5090.
- Two RTX 3090 GPUs.
- Two Mac Studios with 512 GB RAM.

Recommended MVP environment:

- macOS 15+ target if using Apple Translation Framework.
- Xcode 16+.
- Swift + SwiftUI + AppKit.
- Core Audio process taps for audio capture.
- WhisperKit / Argmax OSS for first local ASR backend.
- Optional LAN server using Python, faster-whisper, CTranslate2, and a translation model.

## Functional requirements

### FR-001 — Start and stop subtitle mode

The user can start and stop subtitle generation from a menu bar item or compact control window.

Acceptance criteria:

- Menu bar icon exists.
- Start/Stop action is available.
- Current pipeline state is visible: idle, listening, transcribing, translating, error.
- Stopping the pipeline releases audio taps and model resources cleanly.

### FR-002 — Audio source selection

The user can choose what audio to capture.

Priority order:

1. Capture a specific process/app, such as Safari, Chrome, TV, VLC, IINA, or Plex.
2. Capture system output if process-level capture is not available.
3. Optional fallback: ScreenCaptureKit audio capture.

Acceptance criteria:

- App lists eligible audio-producing processes where feasible.
- App can start capture for selected process or system output.
- Diagnostics show audio levels/RMS so the user can verify capture is active.

### FR-003 — Audio preprocessing

Captured audio is converted into a model-friendly stream.

Acceptance criteria:

- Convert to 16 kHz mono PCM.
- Preserve timestamps from capture time.
- Maintain a rolling ring buffer.
- Avoid heavy allocations in real-time audio callbacks.
- Provide chunks to ASR in configurable windows, initially 0.5–2 seconds.

### FR-004 — Speech detection and chunking

The app should avoid translating silence and should group speech into readable segments.

Acceptance criteria:

- Basic energy-based VAD or model-provided VAD exists.
- Silence longer than a configurable threshold can finalize a segment.
- Partial segments can be replaced or stabilized before display.
- Final segments are retained briefly for subtitle context.

### FR-005 — ASR transcription

The app transcribes English speech into English text.

Acceptance criteria:

- ASR is abstracted behind `ASRService`.
- Mock ASR works for tests and overlay validation.
- First real backend runs locally on the Mac or over LAN.
- ASR returns partial and final transcript segments with timing metadata.
- ASR can be configured for English source language to reduce language-detection overhead.

### FR-006 — Translation to Chinese

The app translates English transcript segments into Chinese.

Acceptance criteria:

- Translation is abstracted behind `TranslationService`.
- Target language can be Simplified Chinese first, with Traditional Chinese as a later option.
- Translation requests preserve subtitle context but avoid long unbounded prompts.
- Translation output is concise enough for subtitles.
- Translation can run locally or on the LAN server.

### FR-007 — Subtitle overlay rendering

Chinese subtitles render above ordinary macOS applications.

Acceptance criteria:

- Transparent, borderless overlay window exists.
- Overlay can appear over normal apps and most full-screen Spaces.
- Overlay uses large readable text with outline/shadow/background options.
- Overlay can show one or two subtitle lines.
- Subtitle line length and wrapping are controlled.
- Overlay can be locked to ignore mouse events.
- Overlay can be unlocked for drag/resize/edit mode.

### FR-008 — Overlay customization

The user can adjust readability.

Acceptance criteria:

- Move overlay.
- Resize overlay.
- Change font size.
- Change maximum number of lines.
- Toggle background pill/box.
- Toggle text shadow/outline.
- Persist overlay frame and style.

### FR-009 — Settings

The app provides settings for model and subtitle behavior.

Acceptance criteria:

- Source app/system capture selection.
- Target language: Simplified Chinese, Traditional Chinese.
- ASR backend: mock, local Mac, remote LAN.
- Translation backend: mock, Apple Translation, remote LAN.
- Latency profile: Fast, Balanced, More Accurate.
- Display options.
- Diagnostics enabled/disabled.

### FR-010 — Diagnostics and benchmark mode

The app must make latency and failures visible.

Acceptance criteria:

- Display audio RMS/input levels.
- Log timestamps for capture, ASR partial, ASR final, translation final, render.
- Compute end-to-end latency.
- Export a JSONL diagnostic log.
- Provide a simple benchmark mode using saved audio clips.

## Non-functional requirements

### Latency

For casual TV viewing, target these rough ranges:

- Excellent: 1.0–2.0 seconds behind speech.
- Acceptable MVP: 2.0–5.0 seconds behind speech.
- Poor: consistently above 6 seconds.

The first version should favor stable readable subtitles over flickery ultra-low-latency partial text.

### Accuracy

The target is contextual help, not professional captioning.

- English ASR should be good enough for common TV dialogue.
- Translation should be fluent Chinese, even if occasionally imperfect.
- Subtitle text should not constantly rewrite once displayed.

### Privacy

- Default pipeline should stay on-device or on a local network.
- Do not send audio to public cloud APIs unless the user deliberately adds that feature later.
- Store logs locally.
- Avoid logging raw audio by default.

### Reliability

- Audio capture should recover from output-device changes where practical.
- The app should fail gracefully when permissions are missing.
- The overlay should not prevent the user from controlling the video app when locked.
- Stop should clean up taps and background tasks.

### Maintainability

- Model backends must be swappable.
- Audio capture, ASR, translation, and subtitle rendering should be separate modules.
- Mocks must exist for ASR and translation so UI and pipeline tests do not need models.

## Out of scope for MVP

- Cloud translation or cloud ASR.
- Microphone conversation translation.
- Speaker diarization.
- OCR or video-frame subtitle extraction.
- Bypassing DRM or protected media restrictions.
- App Store distribution.
- Perfect synchronization with video playback.
- Automatic subtitle file generation.
- Voice dubbing or text-to-speech.

## Known limitations

- No macOS overlay can be guaranteed above every possible system UI. Login screens, lock screens, secure prompts, screen savers, and some protected/full-screen cases may hide or block overlays.
- Some media services may use protected paths or policies that complicate capture. This project should avoid video capture and should not attempt DRM circumvention.
- System audio capture may include notification sounds unless per-process capture is used.
- Translation quality depends heavily on sentence segmentation. Translating incomplete fragments will produce worse Chinese.

