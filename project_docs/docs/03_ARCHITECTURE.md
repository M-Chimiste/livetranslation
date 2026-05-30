# 03 — Architecture

Prepared: 2026-05-20

## High-level architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                     LiveSubtitleTranslator.app                   │
├─────────────────────────────────────────────────────────────────┤
│ Menu bar UI + Settings                                           │
│ Overlay window                                                   │
│ Diagnostics                                                      │
├─────────────────────────────────────────────────────────────────┤
│ SubtitleCoordinator                                              │
│   - consumes transcript segments                                 │
│   - sends translation requests                                   │
│   - stabilizes subtitle output                                   │
│   - updates overlay                                              │
├─────────────────────┬───────────────────────┬───────────────────┤
│ AudioCaptureService │ ASRService             │ TranslationService │
│ Core Audio tap      │ WhisperKit / Remote    │ Apple / Remote     │
└─────────────────────┴───────────────────────┴───────────────────┘
```

## Data flow

```text
Audio callback
  ↓
AudioRingBuffer
  ↓
AudioPreprocessor
  - channel mixdown
  - sample-rate conversion
  - timestamp assignment
  ↓
SpeechChunker / VAD
  ↓
ASRService
  - partial transcript events
  - final transcript segments
  ↓
SubtitleCoordinator
  ↓
TranslationService
  ↓
SubtitleStabilizer
  ↓
SubtitleOverlayWindowController
```

## Core model types

```swift
struct AudioChunk: Sendable {
    let id: UUID
    let captureStartHostTime: UInt64
    let captureEndHostTime: UInt64
    let sampleRate: Double
    let channelCount: Int
    let samples: [Float]
}

struct TranscriptSegment: Identifiable, Sendable {
    enum Stability: Sendable {
        case partial
        case stablePartial
        case final
    }

    let id: UUID
    let sourceLanguage: String
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let createdAt: Date
    let stability: Stability
    let confidence: Double?
}

struct TranslationSegment: Identifiable, Sendable {
    let id: UUID
    let transcriptID: UUID
    let sourceText: String
    let translatedText: String
    let targetLanguage: SubtitleLanguage
    let createdAt: Date
}

enum SubtitleLanguage: String, Codable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
}

struct SubtitleDisplayState: Sendable {
    let primaryLine: String
    let secondaryLine: String?
    let isPartial: Bool
    let updatedAt: Date
}
```

## Service protocols

### AudioCaptureService

```swift
protocol AudioCaptureService: AnyObject {
    var state: AudioCaptureState { get }
    var audioChunks: AsyncStream<AudioChunk> { get }
    var levelSnapshots: AsyncStream<AudioLevelSnapshot> { get }
    var preprocessingDiagnostics: AsyncStream<AudioPreprocessingDiagnostics> { get }

    func availableSources() async throws -> [AudioSource]
    func start(source: AudioSource) async throws
    func stop() async
}
```

Implementation candidates:

- `ProcessTapAudioCaptureService`
- `ScreenCaptureKitAudioCaptureService`
- `MockAudioCaptureService`

### ASRService

```swift
protocol ASRService: AnyObject {
    var events: AsyncStream<ASREvent> { get }

    func configure(_ configuration: ASRConfiguration) async throws
    func start() async throws
    func acceptAudioChunk(_ chunk: AudioChunk) async throws
    func flush() async throws
    func stop() async
}

enum ASREvent: Sendable {
    case partial(TranscriptSegment)
    case final(TranscriptSegment)
    case error(String)
}
```

Implementation candidates:

- `WhisperKitASRService`
- `RemoteASRService`
- `MockASRService`

### TranslationService

```swift
protocol TranslationService: AnyObject {
    func translate(
        segment: TranscriptSegment,
        context: [TranscriptSegment],
        targetLanguage: SubtitleLanguage
    ) async throws -> TranslationSegment
}
```

Implementation candidates:

- `AppleTranslationService`
- `RemoteTranslationService`
- `LLMTranslationService`
- `MockTranslationService`

### SubtitleCoordinator

```swift
@MainActor
final class SubtitleCoordinator: ObservableObject {
    @Published private(set) var displayState: SubtitleDisplayState?
    @Published private(set) var pipelineState: PipelineState = .idle

    func start() async
    func stop() async
    func handleASREvent(_ event: ASREvent) async
}
```

Responsibilities:

- Own the end-to-end pipeline lifecycle.
- Consume ASR events.
- Decide when to translate partial or final segments.
- Maintain recent context.
- Suppress flicker and duplicate subtitles.
- Update overlay display state.
- Record latency metrics.

## Overlay architecture

### Components

```text
SubtitleOverlayWindowController
  ├─ creates NSPanel / NSWindow
  ├─ sets level and collection behavior
  ├─ persists frame
  ├─ toggles edit mode vs locked mode
  └─ hosts SubtitleOverlayView via NSHostingView

SubtitleOverlayView
  ├─ renders translated subtitle lines
  ├─ applies font/background/shadow settings
  └─ exposes edit handles when overlay is unlocked
```

### Window behavior

Initial settings to test:

```swift
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = false
window.level = .statusBar
window.collectionBehavior = [
    .canJoinAllSpaces,
    .fullScreenAuxiliary,
    .stationary
]
window.ignoresMouseEvents = true // when locked
```

Notes:

- `.statusBar` may be preferable to extremely high levels because it is less likely to interfere with system UI.
- Test `.floating`, `.statusBar`, and, only if necessary, higher custom levels.
- In edit mode, use a visible border and allow mouse events.
- In locked mode, make the overlay click-through.

## Audio architecture

### Core Audio callback rules

The callback must be minimal:

1. Validate buffer format.
2. Copy or reference samples safely.
3. Push to ring buffer.
4. Return.

Do not:

- Allocate large arrays repeatedly.
- Run model inference.
- Call SwiftUI/AppKit.
- Await async functions.
- Perform logging on every buffer without throttling.

### Resampling

The ASR input should be 16 kHz mono.

Recommended implementation:

- Capture native device format.
- Convert to `AVAudioPCMBuffer`.
- Use `AVAudioConverter` for sample-rate conversion and mono mixdown.
- Emit `AudioChunk` with Float32 samples.
- Keep Phase 5 chunks continuous, including silence; Phase 6 adds separate VAD speech activity events for future ASR consumption.
- Convert to PCM16 only if remote server protocol requires it.

## Subtitle stabilization

Problem: ASR partial text often changes. Translation of partial text can also change dramatically.

MVP stabilizer rules:

- Do not translate every partial.
- Translate when:
  - ASR marks a segment final, or
  - partial text has been stable for `stablePartialDelayMs`, or
  - punctuation appears and no new words arrive for a short delay.
- Keep the previous final subtitle visible until the next translated segment is ready.
- Suppress repeated text.
- Limit subtitle to two lines.
- Optionally show partial subtitles in a dimmer style, but final-only is acceptable for v1.

Example defaults:

```text
chunkLengthMs: 1000
minSpeechMs: 300
finalSilenceMs: 700
stablePartialDelayMs: 900
subtitleHoldMs: 3500
maxCharsPerLineChinese: 18
maxLines: 2
```

## Backend modes

### Mode 1 — Mock

Used for UI development and tests.

```text
MockAudioCapture → MockASR → MockTranslation → Overlay
```

### Mode 2 — Local Mac

First real MVP.

```text
CoreAudioTap → WhisperKitASR → AppleTranslation → Overlay
```

### Mode 3 — LAN ASR, local translation

Useful if ASR is too slow locally.

```text
CoreAudioTap → RemoteASR → AppleTranslation → Overlay
```

### Mode 4 — Full LAN inference

Best for exploiting NVIDIA GPUs.

```text
CoreAudioTap → RemoteASRAndTranslation → Overlay
```

## Configuration model

```swift
struct AppSettings: Codable, Sendable {
    var targetLanguage: SubtitleLanguage = .simplifiedChinese
    var audioSourceID: String?
    var asrBackend: ASRBackend = .localWhisperKit
    var translationBackend: TranslationBackend = .appleTranslation
    var remoteServerURL: URL?
    var latencyProfile: LatencyProfile = .balanced
    var overlayFrame: CGRect?
    var overlayStyle: OverlayStyle = .default
    var diagnosticsEnabled: Bool = true
}
```

## Error handling

Common errors and UI responses:

| Error | UI response |
|---|---|
| Missing audio capture permission | Show permission instructions and retry button. |
| Tap creation failed | Offer fallback to system capture or ScreenCaptureKit. |
| No audio detected | Show RMS meter and source selection help. |
| ASR model missing | Show download/install model action. |
| Translation unavailable | Switch to remote or mock backend, explain limitation. |
| Remote server unavailable | Show URL/status and reconnect button. |
| Overlay hidden in secure context | Explain macOS limitation. |
