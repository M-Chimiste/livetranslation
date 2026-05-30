# 07 — Benchmark and Test Plan

Prepared: 2026-05-20

The purpose of benchmarking is to find the best latency/quality balance for casual TV viewing, not to win academic ASR or MT benchmarks.

## Benchmark goals

1. Determine whether the M4 Max local path is fast enough.
2. Determine whether LAN GPUs improve latency or accuracy enough to justify the server.
3. Tune chunking and subtitle stabilization.
4. Compare translation backends for Chinese subtitle usefulness.
5. Detect regressions after code/model changes.

## Test content

Use short clips that are legal for personal testing, such as:

- User-owned video clips.
- Public-domain movie dialogue.
- Short samples recorded from a test video.
- Synthetic test speech.

Recommended benchmark set:

| Clip type | Count | Duration | Purpose |
|---|---:|---:|---|
| Clear dialogue | 5 | 30–60 sec | Baseline latency/accuracy. |
| Fast dialogue | 5 | 30–60 sec | Chunking and subtitle readability. |
| Background music/noise | 5 | 30–60 sec | VAD and ASR robustness. |
| Multi-speaker dialogue | 5 | 30–60 sec | Segment stability. |
| Action scene with sparse speech | 5 | 30–60 sec | Silence handling. |

## Metrics

### End-to-end latency

For each subtitle segment:

```text
render_time - audio_segment_end_time
```

Targets:

| Rating | Latency |
|---|---:|
| Excellent | 1.0–2.0 sec |
| Good | 2.0–3.5 sec |
| Acceptable | 3.5–5.0 sec |
| Poor | > 6.0 sec |

### ASR real-time factor

```text
RTF = processing_time_seconds / audio_duration_seconds
```

Interpretation:

- RTF < 0.25: very fast.
- RTF 0.25–0.75: good.
- RTF 0.75–1.0: barely real-time.
- RTF > 1.0: not fast enough without buffering/parallelism.

### Translation latency

Measure:

```text
translation_finished_at - translation_started_at
```

Targets:

- Classic MT: usually sub-second per short segment.
- Local LLM: acceptable if usually under 1 second per segment and output quality is better.

### Subtitle quality subjective score

For each clip, manually score from 1 to 5:

| Score | Meaning |
|---:|---|
| 5 | Natural Chinese, easy to follow. |
| 4 | Minor issues but useful. |
| 3 | Understandable with noticeable awkwardness. |
| 2 | Often confusing. |
| 1 | Not useful. |

Track separately:

- ASR correctness.
- Translation fluency.
- Subtitle timing.
- Flicker/stability.
- Readability.

## Diagnostic timestamps

Record these for every segment:

```text
audio_capture_start
audio_capture_end
chunk_emitted
asr_started
asr_partial_emitted
asr_final_emitted
translation_started
translation_finished
overlay_rendered
```

Write JSONL rows like:

```json
{
  "segment_id": "uuid",
  "backend": "local_whisperkit",
  "translation_backend": "apple_translation",
  "audio_start_ms": 12340,
  "audio_end_ms": 16100,
  "asr_final_at": "2026-05-20T12:00:03.000Z",
  "translation_finished_at": "2026-05-20T12:00:03.090Z",
  "overlay_rendered_at": "2026-05-20T12:00:03.110Z",
  "e2e_latency_ms": 3110,
  "asr_text": "We have to leave before they find us.",
  "translated_text": "我们得在他们找到我们之前离开。"
}
```

## Benchmark modes

### Mode A — Offline file benchmark

Input: WAV file.

Pipeline:

```text
file → ASR → translation → metrics report
```

Pros:

- Repeatable.
- Good for comparing models.
- Does not depend on Core Audio.

Cons:

- Does not test live capture or overlay timing.

### Mode B — Live capture benchmark

Input: audio playing from Mac app/browser.

Pipeline:

```text
Core Audio tap → ASR → translation → overlay → metrics report
```

Pros:

- Tests real app behavior.
- Captures actual overhead.

Cons:

- Less repeatable.
- Needs manual playback.

### Mode C — Server loopback benchmark

Input: saved WAV streamed to LAN server.

Pipeline:

```text
file chunks → WebSocket server → subtitle events → metrics report
```

Pros:

- Tests network and server without needing live video.

Cons:

- Still not identical to Core Audio capture.

## Model benchmark matrix

### Local Mac ASR

Try:

- WhisperKit tiny/base for debug.
- WhisperKit small/medium for balance.
- WhisperKit recommended large-v3 variant if fast enough.
- whisper.cpp as a fallback comparison if integration warrants it.

Record:

- Model name.
- First-load time.
- Warm inference RTF.
- Peak memory.
- Average segment latency.
- Subjective ASR quality.

### LAN ASR

Try:

- faster-whisper `small`, `medium`, `large-v3`, `large-v3-turbo`, or whichever current models are installed.
- FP16 first.
- INT8 if latency/memory need improvement.

Record:

- GPU used.
- CUDA/CuDNN versions.
- Model and compute type.
- RTF and latency.
- VRAM usage.

### Translation

Try:

- Apple Translation.
- NLLB/CTranslate2.
- A local LLM translator.

Record:

- Latency.
- Fluency score.
- Conciseness score.
- Failure cases.

## Unit tests

Add tests for:

- Subtitle line wrapping.
- Duplicate suppression.
- Stable partial detection.
- Settings persistence.
- Translation request context window.
- Remote message encoding/decoding.
- Audio chunk timing math.

## Manual test checklist

Run these before calling the MVP usable:

- Safari video playback.
- Chrome video playback.
- TV app or another streaming app.
- VLC/IINA local video playback.
- Full-screen video.
- Switching Spaces.
- Changing output device.
- Muting system audio.
- Stopping and restarting capture.
- Remote server disconnect and reconnect.
- Missing permission state.
- Overlay lock/unlock.
- Overlay resize while subtitles are updating.

## Regression report template

```text
Date:
Build:
macOS version:
Hardware:
ASR backend/model:
Translation backend/model:
Audio source:
Clip set:
Average E2E latency:
P95 E2E latency:
ASR RTF:
Translation latency avg:
Subjective Chinese score:
Known issues:
Next tuning action:
```

