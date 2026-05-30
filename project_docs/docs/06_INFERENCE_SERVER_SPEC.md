# 06 — LAN Inference Server Spec

Prepared: 2026-05-20

The LAN inference server is optional for the first MVP. It becomes useful once the Mac overlay/audio pipeline works and you want to exploit the RTX GPUs for faster ASR, larger models, or better translation.

## Goals

- Accept audio streamed from the Mac app.
- Run ASR on local network hardware.
- Translate ASR output to Chinese.
- Return subtitle events to the Mac overlay.
- Keep all traffic on the local network.
- Make ASR and translation backends swappable.

## Non-goals

- Public internet service.
- Multi-user production deployment.
- DRM circumvention.
- Cloud API proxying.
- Perfect ultra-low-latency streaming in v1.

## Recommended server stack

```text
Python 3.11+
FastAPI
uvicorn
websockets
faster-whisper
CTranslate2
optional: transformers / sentencepiece for NLLB tokenizer
optional: vLLM or llama.cpp for LLM translation
```

## Server layout

```text
server/
  app.py
  config.py
  models/
    asr.py
    translation.py
    mock.py
  protocols/
    messages.py
  audio/
    pcm.py
    chunker.py
    vad.py
  tests/
  requirements.txt
  README.md
```

## Environment variables

```text
LST_HOST=0.0.0.0
LST_PORT=8765
LST_ASR_BACKEND=faster_whisper
LST_ASR_MODEL=large-v3-turbo
LST_ASR_DEVICE=cuda
LST_ASR_COMPUTE_TYPE=float16
LST_TRANSLATION_BACKEND=nllb_ctranslate2
LST_TRANSLATION_MODEL_PATH=/models/nllb-ct2
LST_TARGET_LANGUAGE=zh-Hans
CUDA_VISIBLE_DEVICES=0
```

For a multi-GPU machine, start simple:

- Run ASR on one GPU.
- Run translation on another GPU if translation model is heavy.
- Scale only after measuring bottlenecks.

## HTTP endpoints

### `GET /health`

Response:

```json
{
  "status": "ok",
  "server_time": "2026-05-20T12:00:00Z",
  "asr_backend": "faster_whisper",
  "translation_backend": "nllb_ctranslate2"
}
```

### `GET /models`

Response:

```json
{
  "asr_models": [
    {
      "id": "large-v3-turbo",
      "backend": "faster_whisper",
      "device": "cuda",
      "compute_type": "float16"
    }
  ],
  "translation_models": [
    {
      "id": "nllb-ct2",
      "backend": "ctranslate2",
      "source_languages": ["en"],
      "target_languages": ["zh-Hans", "zh-Hant"]
    }
  ]
}
```

### `POST /v1/translate`

Request:

```json
{
  "text": "We have to leave before they find us.",
  "source_language": "en",
  "target_language": "zh-Hans",
  "context": [
    "I heard something outside.",
    "Turn off the lights."
  ],
  "style": "subtitle"
}
```

Response:

```json
{
  "translated_text": "我们得在他们找到我们之前离开。",
  "latency_ms": 42,
  "model": "nllb-ct2"
}
```

## WebSocket endpoint

### `WS /v1/stream`

The stream carries JSON control/messages and binary PCM audio frames.

### Client → server: session start

```json
{
  "type": "session.start",
  "session_id": "uuid",
  "audio_format": {
    "encoding": "pcm_f32le",
    "sample_rate": 16000,
    "channels": 1
  },
  "source_language": "en",
  "target_language": "zh-Hans",
  "asr_model": "large-v3-turbo",
  "translation_model": "nllb-ct2",
  "latency_profile": "balanced"
}
```

### Client → server: binary audio

Send binary frames containing raw PCM audio in the declared format.

Recommended initial frame size:

```text
20–100 ms PCM frames from client
server buffers to 0.5–2.0 second ASR chunks
```

### Client → server: flush

```json
{
  "type": "audio.flush",
  "reason": "user_stop"
}
```

### Server → client: ASR partial

```json
{
  "type": "asr.partial",
  "session_id": "uuid",
  "segment_id": "uuid",
  "text": "We have to leave",
  "source_language": "en",
  "audio_start_ms": 12340,
  "audio_end_ms": 14500,
  "confidence": null,
  "created_at": "2026-05-20T12:00:02.100Z"
}
```

### Server → client: ASR final

```json
{
  "type": "asr.final",
  "session_id": "uuid",
  "segment_id": "uuid",
  "text": "We have to leave before they find us.",
  "source_language": "en",
  "audio_start_ms": 12340,
  "audio_end_ms": 16100,
  "confidence": null,
  "created_at": "2026-05-20T12:00:03.000Z"
}
```

### Server → client: translation final

```json
{
  "type": "translation.final",
  "session_id": "uuid",
  "segment_id": "uuid",
  "transcript_text": "We have to leave before they find us.",
  "translated_text": "我们得在他们找到我们之前离开。",
  "target_language": "zh-Hans",
  "latency_ms": 56,
  "created_at": "2026-05-20T12:00:03.090Z"
}
```

### Server → client: subtitle update

```json
{
  "type": "subtitle.update",
  "session_id": "uuid",
  "segment_id": "uuid",
  "lines": ["我们得在他们找到我们之前离开。"],
  "is_partial": false,
  "display_until_ms": 19600,
  "created_at": "2026-05-20T12:00:03.100Z"
}
```

### Server → client: error

```json
{
  "type": "session.error",
  "session_id": "uuid",
  "code": "asr_model_load_failed",
  "message": "Could not load faster-whisper model large-v3-turbo on cuda:0"
}
```

## Initial server ASR strategy

Start with buffered inference, not perfect streaming.

Algorithm:

1. Receive PCM frames.
2. Append to rolling buffer.
3. Run VAD or energy threshold to identify speech.
4. Every 1–2 seconds, run ASR on the current speech window.
5. Emit partial text if it changed meaningfully.
6. On silence or punctuation, emit final segment.
7. Send final segment to translation.

This is simpler than true token streaming and likely good enough for a first TV-subtitle MVP.

## Translation strategy

Start with one of these:

1. CTranslate2 + NLLB/M2M100/MarianMT.
2. Local LLM prompt translator.
3. Mock translator for server/client testing.

Subtitle-style translation rules:

- Keep output concise.
- Do not add explanations.
- Use natural Chinese dialogue.
- Use recent context only, not the full transcript.
- Avoid over-translating names or proper nouns.

## GPU deployment suggestions

### Single GPU server

```bash
CUDA_VISIBLE_DEVICES=0 uvicorn app:app --host 0.0.0.0 --port 8765
```

### Two-process split

```text
Process 1: ASR server on GPU 0
Process 2: Translation server on GPU 1
Mac client talks to one gateway process or the ASR process calls translation process.
```

### Practical starting point

Use one powerful GPU for everything first. Measure before splitting.

## Benchmark metrics

Server should report:

- Audio seconds processed.
- ASR real-time factor.
- ASR latency per segment.
- Translation latency per segment.
- Total server latency.
- GPU model name if available.
- Model names and compute types.

## Security

- Bind only to LAN interface or localhost unless deliberately exposing more.
- Optionally require a shared token in headers or session start.
- Do not expose this server to the public internet.
- Do not store raw audio by default.

