//
//  AudioChunkAssembler.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import Foundation

struct AudioChunkAssembler: Sendable {
    let sampleRate: Double
    let channelCount: Int
    let chunkDuration: TimeInterval

    private var pendingSamples: [Float] = []
    private var pendingHostTimes: [UInt64] = []

    nonisolated init(
        sampleRate: Double = 16_000,
        channelCount: Int = 1,
        chunkDuration: TimeInterval = 1.0
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.chunkDuration = chunkDuration
    }

    nonisolated mutating func append(
        samples: [Float],
        captureStartHostTime: UInt64,
        captureEndHostTime: UInt64
    ) -> [AudioChunk] {
        guard !samples.isEmpty else { return [] }

        pendingSamples.append(contentsOf: samples)
        pendingHostTimes.append(
            contentsOf: Self.interpolatedHostTimes(
                start: captureStartHostTime,
                end: captureEndHostTime,
                sampleCount: samples.count
            )
        )

        var chunks: [AudioChunk] = []
        let chunkSampleCount = max(1, Int(sampleRate * chunkDuration) * channelCount)

        while pendingSamples.count >= chunkSampleCount {
            let chunkSamples = Array(pendingSamples.prefix(chunkSampleCount))
            let chunkHostTimes = Array(pendingHostTimes.prefix(chunkSampleCount))

            chunks.append(
                AudioChunk(
                    captureStartHostTime: chunkHostTimes.first ?? captureStartHostTime,
                    captureEndHostTime: chunkHostTimes.last ?? captureEndHostTime,
                    sampleRate: sampleRate,
                    channelCount: channelCount,
                    samples: chunkSamples
                )
            )

            pendingSamples.removeFirst(chunkSampleCount)
            pendingHostTimes.removeFirst(chunkSampleCount)
        }

        return chunks
    }

    nonisolated mutating func reset() {
        pendingSamples.removeAll(keepingCapacity: true)
        pendingHostTimes.removeAll(keepingCapacity: true)
    }

    nonisolated var pendingSampleCount: Int {
        pendingSamples.count
    }

    private nonisolated static func interpolatedHostTimes(
        start: UInt64,
        end: UInt64,
        sampleCount: Int
    ) -> [UInt64] {
        guard sampleCount > 0 else { return [] }
        guard sampleCount > 1, end >= start else {
            return Array(repeating: start, count: sampleCount)
        }

        return (0..<sampleCount).map { sampleOffset in
            let ratio = Double(sampleOffset) / Double(sampleCount - 1)
            return start + UInt64(Double(end - start) * ratio)
        }
    }
}
