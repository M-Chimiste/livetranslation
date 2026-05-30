//
//  ProcessTapAudioCaptureService.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import AppKit
import CoreAudio
import Foundation

final class ProcessTapAudioCaptureService: AudioCaptureService {
    private nonisolated struct CaptureStreams {
        let audioChunks: AsyncStream<AudioChunk>
        let levelSnapshots: AsyncStream<AudioLevelSnapshot>
        let preprocessingDiagnostics: AsyncStream<AudioPreprocessingDiagnostics>
        let speechActivityEvents: AsyncStream<SpeechActivityEvent>
        let voiceActivityDiagnostics: AsyncStream<VoiceActivityDiagnostics>

        let audioChunkContinuation: AsyncStream<AudioChunk>.Continuation
        let levelContinuation: AsyncStream<AudioLevelSnapshot>.Continuation
        let preprocessingDiagnosticsContinuation: AsyncStream<AudioPreprocessingDiagnostics>.Continuation
        let speechActivityContinuation: AsyncStream<SpeechActivityEvent>.Continuation
        let voiceActivityDiagnosticsContinuation: AsyncStream<VoiceActivityDiagnostics>.Continuation

        static func make() -> CaptureStreams {
            let audioChunkStream = AsyncStream<AudioChunk>.makeStream()
            let levelSnapshotStream = AsyncStream<AudioLevelSnapshot>.makeStream()
            let preprocessingDiagnosticsStream = AsyncStream<AudioPreprocessingDiagnostics>.makeStream()
            let speechActivityStream = AsyncStream<SpeechActivityEvent>.makeStream()
            let voiceActivityDiagnosticsStream = AsyncStream<VoiceActivityDiagnostics>.makeStream()

            return CaptureStreams(
                audioChunks: audioChunkStream.stream,
                levelSnapshots: levelSnapshotStream.stream,
                preprocessingDiagnostics: preprocessingDiagnosticsStream.stream,
                speechActivityEvents: speechActivityStream.stream,
                voiceActivityDiagnostics: voiceActivityDiagnosticsStream.stream,
                audioChunkContinuation: audioChunkStream.continuation,
                levelContinuation: levelSnapshotStream.continuation,
                preprocessingDiagnosticsContinuation: preprocessingDiagnosticsStream.continuation,
                speechActivityContinuation: speechActivityStream.continuation,
                voiceActivityDiagnosticsContinuation: voiceActivityDiagnosticsStream.continuation
            )
        }

        func finish() {
            audioChunkContinuation.finish()
            levelContinuation.finish()
            preprocessingDiagnosticsContinuation.finish()
            speechActivityContinuation.finish()
            voiceActivityDiagnosticsContinuation.finish()
        }
    }

    private(set) var state: AudioCaptureState = .idle

    var audioChunks: AsyncStream<AudioChunk> { streams.audioChunks }
    var levelSnapshots: AsyncStream<AudioLevelSnapshot> { streams.levelSnapshots }
    var preprocessingDiagnostics: AsyncStream<AudioPreprocessingDiagnostics> { streams.preprocessingDiagnostics }
    var speechActivityEvents: AsyncStream<SpeechActivityEvent> { streams.speechActivityEvents }
    var voiceActivityDiagnostics: AsyncStream<VoiceActivityDiagnostics> { streams.voiceActivityDiagnostics }

    private var streams = CaptureStreams.make()
    private var tapDescription: CATapDescription?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var currentSampleRate: Double = 0
    private var currentChannelCount = 0
    private var voiceActivitySettings: VoiceActivitySettings = .defaults
    private var ringBuffer: AudioRingBuffer?
    private var preprocessingTask: Task<Void, Never>?
    private let ioQueue = DispatchQueue(label: "LiveSubtitleTranslator.ProcessTapAudioCaptureService.IO", qos: .userInitiated)

    init() {}

    deinit {
        stopSynchronously()
        streams.finish()
    }

    func updateVoiceActivitySettings(_ settings: VoiceActivitySettings) {
        voiceActivitySettings = settings
    }

    func availableSources() async throws -> [AudioSource] {
        [.systemOutput] + listProcessSources()
    }

    func start(source: AudioSource) async throws {
        guard source.kind == .systemOutput else {
            state = .error(AudioCaptureError.selectedAppCaptureUnavailable.localizedDescription)
            throw AudioCaptureError.selectedAppCaptureUnavailable
        }

        guard !state.isRunning else { return }

        state = .starting

        do {
            try await startSystemOutputTap()
            state = .capturing
        } catch {
            await stopCaptureResources()
            state = .error(error.localizedDescription)
            throw error
        }
    }

    func stop() async {
        guard state != .idle else { return }

        state = .stopping
        await stopCaptureResources()
        state = .idle
    }

    private func startSystemOutputTap() async throws {
        if hasActiveCaptureResources {
            await stopCaptureResources()
        }
        renewStreams()

        let tapUUID = UUID()
        let description = Self.makeSystemOutputTapDescription(
            tapUUID: tapUUID
        )

        var createdTapID = AudioObjectID(kAudioObjectUnknown)
        try Self.check(
            AudioHardwareCreateProcessTap(description, &createdTapID),
            operation: "Create Core Audio process tap"
        )

        tapDescription = description
        tapID = createdTapID

        let streamFormat = try Self.property(
            AudioStreamBasicDescription.self,
            objectID: createdTapID,
            selector: kAudioTapPropertyFormat
        )
        guard streamFormat.isFloat32PCM else {
            throw AudioCaptureError.invalidAudioFormat
        }

        currentSampleRate = streamFormat.mSampleRate
        currentChannelCount = Int(streamFormat.mChannelsPerFrame)
        let sampleRate = currentSampleRate
        let channelCount = max(1, currentChannelCount)
        let ringBuffer = AudioRingBuffer(
            capacityFrames: max(1, Int(sampleRate * 10)),
            channelCount: channelCount,
            sampleRate: sampleRate
        )
        self.ringBuffer = ringBuffer
        startPreprocessingTask(
            ringBuffer: ringBuffer,
            sourceSampleRate: sampleRate,
            sourceChannelCount: channelCount,
            voiceActivitySettings: voiceActivitySettings
        )

        let aggregateUID = "com.theseusresearch.LiveSubtitleTranslator.capture.\(UUID().uuidString)"
        let aggregateDescription = Self.makeAggregateDeviceDescription(
            aggregateUID: aggregateUID
        )

        var createdAggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        try Self.check(
            AudioHardwareCreateAggregateDevice(
                aggregateDescription as CFDictionary,
                &createdAggregateDeviceID
            ),
            operation: "Create private aggregate capture device"
        )

        aggregateDeviceID = createdAggregateDeviceID
        let tapUID = try Self.tapUID(for: createdTapID)
        try Self.attachTapToAggregateDevice(
            aggregateDeviceID: createdAggregateDeviceID,
            tapUID: tapUID
        )

        let levelContinuation = streams.levelContinuation
        let ioBlock: AudioDeviceIOBlock = { _, inputData, inputTime, _, _ in
            let captureStartHostTime = inputTime.pointee.mHostTime == 0
                ? AudioGetCurrentHostTime()
                : inputTime.pointee.mHostTime
            let snapshot = AudioLevelCalculator.snapshot(
                bufferList: inputData,
                sampleRate: sampleRate,
                channelCount: channelCount
            )
            levelContinuation.yield(snapshot)
            ringBuffer.write(
                bufferList: inputData,
                captureStartHostTime: captureStartHostTime
            )
        }

        let createdIOProcID = try await createIOProcIDWithRetry(
            deviceID: createdAggregateDeviceID,
            ioBlock: ioBlock
        )
        ioProcID = createdIOProcID

        try await Self.retryCoreAudioOperation(
            operation: "Start aggregate capture device"
        ) {
            AudioDeviceStart(createdAggregateDeviceID, createdIOProcID)
        }
    }

    private func createIOProcIDWithRetry(
        deviceID: AudioObjectID,
        ioBlock: @escaping AudioDeviceIOBlock
    ) async throws -> AudioDeviceIOProcID {
        var createdIOProcID: AudioDeviceIOProcID?

        try await Self.retryCoreAudioOperation(
            operation: "Create aggregate capture IOProc"
        ) {
            AudioDeviceCreateIOProcIDWithBlock(
                &createdIOProcID,
                deviceID,
                ioQueue,
                ioBlock
            )
        }

        guard let createdIOProcID else {
            throw AudioCaptureError.coreAudio(
                operation: "Create aggregate capture IOProc",
                status: kAudioHardwareUnspecifiedError
            )
        }

        return createdIOProcID
    }

    static func makeSystemOutputTapDescription(
        tapUUID: UUID
    ) -> CATapDescription {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Live Subtitle Translator System Output Tap"
        description.uuid = tapUUID
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior.unmuted
        description.deviceUID = nil
        description.stream = 0
        return description
    }

    static func makeAggregateDeviceDescription(
        aggregateUID: String
    ) -> [String: Any] {
        [
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceNameKey: "Live Subtitle Translator Capture",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [] as CFArray
        ]
    }

    private static func tapUID(for tapID: AudioObjectID) throws -> CFString {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString>.stride)
        var tapUID = "" as CFString

        try check(
            withUnsafeMutablePointer(to: &tapUID) { tapUIDPointer in
                AudioObjectGetPropertyData(
                    tapID,
                    &address,
                    0,
                    nil,
                    &size,
                    tapUIDPointer
                )
            },
            operation: "Read Core Audio tap UID"
        )

        return tapUID
    }

    private static func attachTapToAggregateDevice(
        aggregateDeviceID: AudioObjectID,
        tapUID: CFString
    ) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let tapList = [tapUID] as CFArray
        let size = UInt32(MemoryLayout<CFArray>.stride)

        try check(
            withUnsafePointer(to: tapList) { tapListPointer in
                AudioObjectSetPropertyData(
                    aggregateDeviceID,
                    &address,
                    0,
                    nil,
                    size,
                    tapListPointer
                )
            },
            operation: "Attach Core Audio tap to aggregate device"
        )
    }

    private func startPreprocessingTask(
        ringBuffer: AudioRingBuffer,
        sourceSampleRate: Double,
        sourceChannelCount: Int,
        voiceActivitySettings: VoiceActivitySettings
    ) {
        preprocessingTask?.cancel()

        let audioChunkContinuation = streams.audioChunkContinuation
        let diagnosticsContinuation = streams.preprocessingDiagnosticsContinuation
        let speechActivityContinuation = streams.speechActivityContinuation
        let voiceActivityDiagnosticsContinuation = streams.voiceActivityDiagnosticsContinuation
        preprocessingTask = Task.detached(priority: .userInitiated) {
            let resampler = AudioResampler(
                sourceSampleRate: sourceSampleRate,
                sourceChannelCount: sourceChannelCount
            )
            var assembler = AudioChunkAssembler()
            var voiceActivityDetector = EnergyVoiceActivityDetector(
                settings: voiceActivitySettings
            )
            var emittedChunkCount = 0
            var lastChunkDuration: TimeInterval?
            let maxReadFrames = max(1, Int(sourceSampleRate / 10))

            while !Task.isCancelled {
                let read = ringBuffer.read(maxFrames: maxReadFrames)

                if !read.isEmpty {
                    do {
                        let resampledSamples = try resampler.convert(
                            interleavedSamples: read.samples
                        )
                        let chunks = assembler.append(
                            samples: resampledSamples,
                            captureStartHostTime: read.captureStartHostTime,
                            captureEndHostTime: read.captureEndHostTime
                        )

                        for chunk in chunks {
                            audioChunkContinuation.yield(chunk)
                            emittedChunkCount += 1
                            lastChunkDuration = chunk.duration

                            let speechEvents = voiceActivityDetector.process(chunk)
                            for speechEvent in speechEvents {
                                speechActivityContinuation.yield(speechEvent)
                            }
                            voiceActivityDiagnosticsContinuation.yield(
                                voiceActivityDetector.currentDiagnostics
                            )
                        }
                    } catch {
                        // Keep the realtime callback isolated from converter failures. Future diagnostics
                        // can surface converter-specific errors once preprocessing has its own UI state.
                    }
                }

                let diagnostics = ringBuffer.diagnostics
                diagnosticsContinuation.yield(
                    AudioPreprocessingDiagnostics(
                        emittedChunkCount: emittedChunkCount,
                        lastChunkDuration: lastChunkDuration,
                        queueDepthFrames: diagnostics.queueDepthFrames,
                        droppedFrames: diagnostics.droppedFrames,
                        callbackCount: diagnostics.callbackCount,
                        capturedFrameCount: diagnostics.capturedFrameCount
                    )
                )

                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    private var hasActiveCaptureResources: Bool {
        preprocessingTask != nil
            || ringBuffer != nil
            || aggregateDeviceID != AudioObjectID(kAudioObjectUnknown)
            || tapID != AudioObjectID(kAudioObjectUnknown)
            || ioProcID != nil
    }

    private func stopCaptureResources() async {
        stopCoreAudioResources()

        let task = preprocessingTask
        preprocessingTask = nil
        task?.cancel()
        await task?.value

        resetPreprocessingResources()

        try? await Task.sleep(for: .milliseconds(100))
    }

    private func stopSynchronously() {
        stopCoreAudioResources()
        preprocessingTask?.cancel()
        preprocessingTask = nil
        resetPreprocessingResources()
    }

    private func stopCoreAudioResources() {
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown), let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }

        ioProcID = nil

        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }

        aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)

        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
        }

        tapID = AudioObjectID(kAudioObjectUnknown)
        tapDescription = nil
        currentSampleRate = 0
        currentChannelCount = 0
    }

    private func resetPreprocessingResources() {
        ringBuffer?.reset()
        ringBuffer = nil
        streams.preprocessingDiagnosticsContinuation.yield(.zero)
        streams.voiceActivityDiagnosticsContinuation.yield(.zero)
        streams.finish()
    }

    private func renewStreams() {
        streams.finish()
        streams = CaptureStreams.make()
    }

    private func listProcessSources() -> [AudioSource] {
        let objectIDs: [AudioObjectID]

        do {
            objectIDs = try Self.arrayProperty(
                AudioObjectID.self,
                objectID: AudioObjectID(kAudioObjectSystemObject),
                selector: kAudioHardwarePropertyProcessObjectList
            )
        } catch {
            return []
        }

        return objectIDs.compactMap { processObjectID in
            let pid: pid_t

            do {
                pid = try Self.property(
                    pid_t.self,
                    objectID: processObjectID,
                    selector: kAudioProcessPropertyPID
                )
            } catch {
                return nil
            }

            let isRunningOutput = (try? Self.property(
                UInt32.self,
                objectID: processObjectID,
                selector: kAudioProcessPropertyIsRunningOutput
            )) ?? 0
            guard isRunningOutput != 0 else { return nil }

            let bundleID = try? Self.cfStringProperty(
                objectID: processObjectID,
                selector: kAudioProcessPropertyBundleID
            )
            let appName = NSRunningApplication(processIdentifier: pid)?.localizedName
            let displayName = appName ?? bundleID ?? "Process \(pid)"

            return AudioSource(
                id: "process-\(processObjectID)",
                displayName: displayName,
                kind: .process,
                processObjectID: processObjectID,
                processID: pid,
                bundleID: bundleID
            )
        }
        .sorted { lhs, rhs in
            lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func property<T>(
        _ type: T.Type,
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        let rawValue = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<T>.size,
            alignment: MemoryLayout<T>.alignment
        )
        defer {
            rawValue.deallocate()
        }

        try check(
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &size,
                rawValue
            ),
            operation: "Read Core Audio property \(selector)"
        )

        return rawValue.load(as: T.self)
    }

    private static func arrayProperty<T>(
        _ type: T.Type,
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> [T] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0

        try check(
            AudioObjectGetPropertyDataSize(
                objectID,
                &address,
                0,
                nil,
                &size
            ),
            operation: "Read Core Audio property size \(selector)"
        )

        let count = Int(size) / MemoryLayout<T>.stride
        guard count > 0 else { return [] }

        let rawValues = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<T>.alignment
        )
        defer {
            rawValues.deallocate()
        }

        try check(
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &size,
                rawValues
            ),
            operation: "Read Core Audio array property \(selector)"
        )

        let typedValues = rawValues.bindMemory(to: T.self, capacity: count)
        return (0..<count).map { typedValues[$0] }
    }

    private static func cfStringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        try check(
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &size,
                &value
            ),
            operation: "Read Core Audio string property \(selector)"
        )

        return value?.takeRetainedValue() as String?
    }

    private static func defaultOutputDeviceUID() throws -> String {
        if let outputDeviceUID = try? deviceUID(
            forSystemSelector: kAudioHardwarePropertyDefaultOutputDevice
        ) {
            return outputDeviceUID
        }

        return try deviceUID(forSystemSelector: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    private static func deviceUID(forSystemSelector selector: AudioObjectPropertySelector) throws -> String {
        let outputDeviceID = try property(
            AudioObjectID.self,
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: selector
        )
        guard outputDeviceID != AudioObjectID(kAudioObjectUnknown),
              let outputDeviceUID = try cfStringProperty(
                objectID: outputDeviceID,
                selector: kAudioDevicePropertyDeviceUID
              ),
              !outputDeviceUID.isEmpty
        else {
            throw AudioCaptureError.sourceUnavailable
        }

        return outputDeviceUID
    }

    private static func retryCoreAudioOperation(
        operation: String,
        maxAttempts: Int = 20,
        delay: Duration = .milliseconds(50),
        _ body: () -> OSStatus
    ) async throws {
        var lastStatus = kAudioHardwareUnspecifiedError

        for attempt in 0..<maxAttempts {
            let status = body()
            guard status != noErr else { return }

            lastStatus = status
            guard attempt < maxAttempts - 1 else { break }
            try await Task.sleep(for: delay)
        }

        throw AudioCaptureError.coreAudio(operation: operation, status: lastStatus)
    }

    private static func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw AudioCaptureError.coreAudio(operation: operation, status: status)
        }
    }
}

private extension AudioStreamBasicDescription {
    var isFloat32PCM: Bool {
        mFormatID == kAudioFormatLinearPCM
            && mBitsPerChannel == 32
            && (mFormatFlags & kAudioFormatFlagIsFloat) != 0
    }
}
