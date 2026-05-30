//
//  AudioRingBuffer.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import CoreAudio
import Foundation
import os.lock

struct AudioRingBufferDiagnostics: Equatable, Sendable {
    let queueDepthFrames: Int
    let droppedFrames: Int
    let capacityFrames: Int
    let callbackCount: Int
    let capturedFrameCount: Int
}

struct AudioRingBufferRead: Equatable, Sendable {
    let samples: [Float]
    let frameCount: Int
    let channelCount: Int
    let sampleRate: Double
    let captureStartHostTime: UInt64
    let captureEndHostTime: UInt64

    nonisolated var isEmpty: Bool {
        frameCount == 0
    }
}

final class AudioRingBuffer: @unchecked Sendable {
    let capacityFrames: Int
    let channelCount: Int
    let sampleRate: Double

    private nonisolated(unsafe) var lock = os_unfair_lock_s()
    private nonisolated(unsafe) var samples: [Float]
    private nonisolated(unsafe) var hostTimes: [UInt64]
    private nonisolated(unsafe) var readFrameIndex = 0
    private nonisolated(unsafe) var writeFrameIndex = 0
    private nonisolated(unsafe) var availableFrameCount = 0
    private nonisolated(unsafe) var droppedFrameCount = 0
    private nonisolated(unsafe) var callbackCount = 0
    private nonisolated(unsafe) var capturedFrameCount = 0

    nonisolated init(capacityFrames: Int, channelCount: Int, sampleRate: Double) {
        self.capacityFrames = max(1, capacityFrames)
        self.channelCount = max(1, channelCount)
        self.sampleRate = sampleRate
        self.samples = Array(repeating: 0, count: max(1, capacityFrames) * max(1, channelCount))
        self.hostTimes = Array(repeating: 0, count: max(1, capacityFrames))
    }

    nonisolated func write(
        interleavedSamples inputSamples: [Float],
        captureStartHostTime: UInt64,
        captureEndHostTime: UInt64? = nil
    ) {
        let frameCount = inputSamples.count / channelCount
        guard frameCount > 0 else { return }

        withLock {
            writeLocked(
                interleavedSamples: inputSamples,
                sourceStartFrame: 0,
                sourceFrameCount: frameCount,
                captureStartHostTime: captureStartHostTime,
                captureEndHostTime: captureEndHostTime ?? estimatedEndHostTime(
                    startHostTime: captureStartHostTime,
                    frameCount: frameCount,
                    sampleRate: sampleRate
                )
            )
        }
    }

    nonisolated func write(
        bufferList: UnsafePointer<AudioBufferList>,
        captureStartHostTime: UInt64
    ) {
        guard tryWithLock({
            writeBufferListLocked(
                bufferList: bufferList,
                captureStartHostTime: captureStartHostTime
            )
        }) != nil else {
            return
        }
    }

    nonisolated func read(maxFrames: Int) -> AudioRingBufferRead {
        withLock {
            let framesToRead = min(max(0, maxFrames), availableFrameCount)
            guard framesToRead > 0 else {
                return AudioRingBufferRead(
                    samples: [],
                    frameCount: 0,
                    channelCount: channelCount,
                    sampleRate: sampleRate,
                    captureStartHostTime: 0,
                    captureEndHostTime: 0
                )
            }

            var outputSamples = Array(repeating: Float(0), count: framesToRead * channelCount)
            let startHostTime = hostTimes[readFrameIndex]
            var endHostTime = startHostTime

            for frameOffset in 0..<framesToRead {
                let sourceFrame = (readFrameIndex + frameOffset) % capacityFrames
                let outputFrameStart = frameOffset * channelCount
                let sourceFrameStart = sourceFrame * channelCount

                for channel in 0..<channelCount {
                    outputSamples[outputFrameStart + channel] = samples[sourceFrameStart + channel]
                }

                endHostTime = hostTimes[sourceFrame]
            }

            readFrameIndex = (readFrameIndex + framesToRead) % capacityFrames
            availableFrameCount -= framesToRead

            return AudioRingBufferRead(
                samples: outputSamples,
                frameCount: framesToRead,
                channelCount: channelCount,
                sampleRate: sampleRate,
                captureStartHostTime: startHostTime,
                captureEndHostTime: endHostTime
            )
        }
    }

    nonisolated func reset() {
        withLock {
            for index in samples.indices {
                samples[index] = 0
            }
            for index in hostTimes.indices {
                hostTimes[index] = 0
            }
            readFrameIndex = 0
            writeFrameIndex = 0
            availableFrameCount = 0
            droppedFrameCount = 0
            callbackCount = 0
            capturedFrameCount = 0
        }
    }

    nonisolated var diagnostics: AudioRingBufferDiagnostics {
        withLock {
            AudioRingBufferDiagnostics(
                queueDepthFrames: availableFrameCount,
                droppedFrames: droppedFrameCount,
                capacityFrames: capacityFrames,
                callbackCount: callbackCount,
                capturedFrameCount: capturedFrameCount
            )
        }
    }

    private nonisolated func writeBufferListLocked(
        bufferList: UnsafePointer<AudioBufferList>,
        captureStartHostTime: UInt64
    ) {
        withUnsafePointer(to: bufferList.pointee.mBuffers) { pointer in
            let firstBuffer = UnsafeRawPointer(pointer).assumingMemoryBound(to: AudioBuffer.self)
            let bufferCount = Int(bufferList.pointee.mNumberBuffers)
            let frameCount = Self.frameCount(
                firstBuffer: firstBuffer,
                bufferCount: bufferCount,
                channelCount: channelCount
            )
            callbackCount += 1
            capturedFrameCount += frameCount
            guard frameCount > 0 else { return }

            let captureEndHostTime = estimatedEndHostTime(
                startHostTime: captureStartHostTime,
                frameCount: frameCount,
                sampleRate: sampleRate
            )
            let sourceStartFrame = max(0, frameCount - capacityFrames)

            if sourceStartFrame > 0 {
                droppedFrameCount += sourceStartFrame
            }

            makeRoomForIncomingFrames(frameCount - sourceStartFrame)

            for sourceFrame in sourceStartFrame..<frameCount {
                let hostTime = interpolatedHostTime(
                    start: captureStartHostTime,
                    end: captureEndHostTime,
                    frameOffset: sourceFrame,
                    frameCount: frameCount
                )
                writeFrame(hostTime: hostTime) { channel in
                    Self.sample(
                        firstBuffer: firstBuffer,
                        bufferCount: bufferCount,
                        frame: sourceFrame,
                        channel: channel,
                        channelCount: channelCount
                    )
                }
            }
        }
    }

    private nonisolated func writeLocked(
        interleavedSamples inputSamples: [Float],
        sourceStartFrame: Int,
        sourceFrameCount: Int,
        captureStartHostTime: UInt64,
        captureEndHostTime: UInt64
    ) {
        let adjustedStartFrame = max(sourceStartFrame, sourceFrameCount - capacityFrames)
        if adjustedStartFrame > sourceStartFrame {
            droppedFrameCount += adjustedStartFrame - sourceStartFrame
        }

        makeRoomForIncomingFrames(sourceFrameCount - adjustedStartFrame)

        for sourceFrame in adjustedStartFrame..<sourceFrameCount {
            let hostTime = interpolatedHostTime(
                start: captureStartHostTime,
                end: captureEndHostTime,
                frameOffset: sourceFrame,
                frameCount: sourceFrameCount
            )
            writeFrame(hostTime: hostTime) { channel in
                inputSamples[(sourceFrame * channelCount) + channel]
            }
        }
    }

    private nonisolated func writeFrame(
        hostTime: UInt64,
        sampleAtChannel: (Int) -> Float
    ) {
        let destinationFrameStart = writeFrameIndex * channelCount
        hostTimes[writeFrameIndex] = hostTime

        for channel in 0..<channelCount {
            samples[destinationFrameStart + channel] = sampleAtChannel(channel)
        }

        writeFrameIndex = (writeFrameIndex + 1) % capacityFrames
        availableFrameCount += 1
    }

    private nonisolated func makeRoomForIncomingFrames(_ incomingFrameCount: Int) {
        let overflowFrameCount = max(0, availableFrameCount + incomingFrameCount - capacityFrames)
        guard overflowFrameCount > 0 else { return }

        readFrameIndex = (readFrameIndex + overflowFrameCount) % capacityFrames
        availableFrameCount -= overflowFrameCount
        droppedFrameCount += overflowFrameCount
    }

    private nonisolated func estimatedEndHostTime(
        startHostTime: UInt64,
        frameCount: Int,
        sampleRate: Double
    ) -> UInt64 {
        let durationNanos = UInt64((Double(frameCount) / sampleRate) * 1_000_000_000)
        return startHostTime + AudioConvertNanosToHostTime(durationNanos)
    }

    private nonisolated func interpolatedHostTime(
        start: UInt64,
        end: UInt64,
        frameOffset: Int,
        frameCount: Int
    ) -> UInt64 {
        guard frameCount > 1, end >= start else { return start }
        let ratio = Double(frameOffset) / Double(frameCount - 1)
        return start + UInt64(Double(end - start) * ratio)
    }

    private nonisolated func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lock)
        defer {
            os_unfair_lock_unlock(&lock)
        }
        return body()
    }

    private nonisolated func tryWithLock<T>(_ body: () -> T) -> T? {
        guard os_unfair_lock_trylock(&lock) else { return nil }
        defer {
            os_unfair_lock_unlock(&lock)
        }
        return body()
    }

    private nonisolated static func frameCount(
        firstBuffer: UnsafePointer<AudioBuffer>,
        bufferCount: Int,
        channelCount: Int
    ) -> Int {
        guard bufferCount > 0 else { return 0 }
        let firstAudioBuffer = firstBuffer[0]

        if bufferCount == 1 {
            let sampleCount = Int(firstAudioBuffer.mDataByteSize) / MemoryLayout<Float>.stride
            return sampleCount / max(1, channelCount)
        }

        return Int(firstAudioBuffer.mDataByteSize) / MemoryLayout<Float>.stride
    }

    private nonisolated static func sample(
        firstBuffer: UnsafePointer<AudioBuffer>,
        bufferCount: Int,
        frame: Int,
        channel: Int,
        channelCount: Int
    ) -> Float {
        guard bufferCount > 0 else { return 0 }

        if bufferCount == 1 {
            let buffer = firstBuffer[0]
            guard let data = buffer.mData else { return 0 }
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.stride
            let index = (frame * channelCount) + channel
            guard index < sampleCount else { return 0 }
            return data.bindMemory(to: Float.self, capacity: sampleCount)[index]
        }

        let bufferIndex = min(channel, bufferCount - 1)
        let buffer = firstBuffer[bufferIndex]
        guard let data = buffer.mData else { return 0 }
        let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.stride
        guard frame < sampleCount else { return 0 }
        return data.bindMemory(to: Float.self, capacity: sampleCount)[frame]
    }
}
