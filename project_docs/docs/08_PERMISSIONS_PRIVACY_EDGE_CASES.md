# 08 — Permissions, Privacy, and Edge Cases

Prepared: 2026-05-20

## Permissions

### System audio capture

Add this to `Info.plist`:

```xml
<key>NSAudioCaptureUsageDescription</key>
<string>Live Subtitle Translator captures audio playing on this Mac to generate local translated subtitles.</string>
```

The app should show a friendly explanation before requesting permission:

```text
This app needs access to Mac audio so it can generate subtitles from what you are watching. Audio is processed locally or on your local network according to your settings.
```

### Screen recording

Do not request Screen Recording permission for the primary path. It should only be needed if a ScreenCaptureKit fallback is added.

### Microphone

Do not request microphone permission for MVP unless microphone translation is added later.

### Accessibility

Not required for subtitle overlay, unless global hotkeys, app control, or UI automation features are added. Avoid requesting Accessibility permission in the MVP.

## Privacy principles

- Default to local processing.
- Do not use public cloud APIs by default.
- Do not store raw audio by default.
- Keep diagnostic logs local.
- Let the user disable diagnostic logging.
- If LAN mode is used, show the server URL clearly.
- Do not expose the LAN server publicly.

## Data handling

### Audio

Default:

- Process in memory.
- Do not write to disk.
- Allow temporary saved debug audio only behind an explicit diagnostics toggle.

### Transcripts/translations

Default:

- Keep recent context in memory.
- Write text logs only when diagnostics are enabled.
- Allow user to clear logs.

### Settings

Persist:

- Overlay frame and style.
- Target language.
- Backend choice.
- Server URL.
- Latency profile.

Do not persist:

- Raw audio.
- Full transcripts unless diagnostics are enabled.

## DRM and protected content

The app should not attempt to bypass DRM, capture protected video, or extract subtitle/video data from streaming services.

This project is intended to capture audio for live personal accessibility/context. If a service or protected content path prevents capture, the app should fail gracefully and explain that the content may be protected or unavailable for capture.

## Overlay limitations

No third-party macOS overlay is guaranteed to appear above every possible UI surface.

Likely to work:

- Normal app windows.
- Many browser/video app windows.
- Many full-screen app Spaces with correct collection behavior.

May not work:

- Login window.
- Lock screen.
- Secure system prompts.
- Screen saver.
- Some DRM/protected full-screen playback contexts.
- Some exclusive display or game modes.

The app should include help text:

```text
The subtitle overlay appears above most apps, but macOS may hide overlays in secure or protected contexts.
```

## Audio edge cases

### Notifications and other apps

Problem: system-wide capture may include notification sounds or other app audio.

Mitigations:

- Prefer per-process capture.
- Add app exclusion list.
- Encourage user to enable Focus mode while watching.

### Output device changes

Problem: user switches from speakers to headphones.

Mitigations:

- Watch for audio device changes.
- Stop and recreate tap/aggregate device if needed.
- Show reconnecting state.

### Muted/low volume

Core Audio tap behavior may differ depending on tap point. Diagnostics should show actual captured RMS. If the user hears audio but RMS is zero, offer restart capture/source selection.

### Multi-channel audio

Problem: streaming audio may be stereo, 5.1, or routed through virtual devices.

Mitigations:

- Mix down to mono.
- Show detected format.
- Test common output configurations.

## ASR edge cases

### Music and effects

Problem: ASR may hallucinate during music or noise.

Mitigations:

- Use VAD.
- Require minimum speech confidence or minimum text stability.
- Suppress repeated nonsense.

### Very fast dialogue

Problem: subtitles lag or overrun.

Mitigations:

- Use Balanced/More Accurate latency modes.
- Increase context window.
- Prefer final/stable partials.

### Accents and mixed languages

Problem: ASR may misrecognize non-English or code-switched speech.

Mitigations:

- Let user set source language.
- Add automatic language detection later if needed.
- Log source language/confidence when backend provides it.

## Translation edge cases

### Incomplete sentences

Problem: translating fragments creates awkward Chinese.

Mitigations:

- Translate on final segments when possible.
- Use punctuation and silence thresholds.
- Provide recent context.

### Names and terms

Problem: names may be translated incorrectly.

Mitigations:

- Keep a custom glossary later.
- Add prompt hints for LLM translator.
- Preserve capitalization/proper noun cues in context.

### Subtitle length

Problem: literal Chinese may be too long.

Mitigations:

- Use concise subtitle translation style.
- Enforce max lines.
- Add LLM compression later.

## LAN server edge cases

### Server unavailable

Mitigation:

- Show disconnected state.
- Allow retry.
- Fall back to local backend if available.

### Network jitter

Mitigation:

- Buffer audio chunks.
- Use timestamps, not arrival time, for subtitle timing.
- Log network round-trip where practical.

### GPU contention

Mitigation:

- Show server health/model status.
- Benchmark with dedicated GPU.
- Use environment variables to pin GPU.

## User-visible help text

Suggested About/Help content:

```text
Live Subtitle Translator listens to audio playing on your Mac and generates translated subtitles. It is designed for personal viewing and accessibility/context. It does not capture video and does not bypass protected content systems. Audio can be processed on this Mac or on a server you run on your local network.
```

