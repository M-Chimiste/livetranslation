//
//  AudioLevel.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import CoreAudio
import Foundation

struct AudioLevelSnapshot: Equatable, Sendable {
    let rms: Float
    let peak: Float
    let timestamp: Date
    let sampleRate: Double
    let channelCount: Int

    nonisolated init(
        rms: Float,
        peak: Float,
        timestamp: Date,
        sampleRate: Double,
        channelCount: Int
    ) {
        self.rms = rms
        self.peak = peak
        self.timestamp = timestamp
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    nonisolated static let zero = AudioLevelSnapshot(
        rms: 0,
        peak: 0,
        timestamp: Date(timeIntervalSince1970: 0),
        sampleRate: 0,
        channelCount: 0
    )

    nonisolated var rmsDecibels: Double {
        Self.decibels(for: rms)
    }

    nonisolated var peakDecibels: Double {
        Self.decibels(for: peak)
    }

    nonisolated var rmsDisplayValue: String {
        Self.normalizedDisplayValue(for: rms, decibels: rmsDecibels)
    }

    nonisolated var peakDisplayValue: String {
        Self.normalizedDisplayValue(for: peak, decibels: peakDecibels)
    }

    nonisolated private static func decibels(for value: Float) -> Double {
        guard value > 0 else { return -.infinity }
        return 20 * log10(Double(value))
    }

    nonisolated private static func normalizedDisplayValue(for value: Float, decibels: Double) -> String {
        let normalizedValue = String(format: "%.3f", min(max(value, 0), 1))
        let decibelValue = decibels.isFinite ? String(format: "%.1f dBFS", decibels) : "-∞ dBFS"
        return "\(normalizedValue) (\(decibelValue))"
    }
}

enum AudioLevelCalculator {
    nonisolated static func snapshot(
        samples: [Float],
        timestamp: Date = Date(),
        sampleRate: Double,
        channelCount: Int
    ) -> AudioLevelSnapshot {
        guard !samples.isEmpty else {
            return AudioLevelSnapshot(
                rms: 0,
                peak: 0,
                timestamp: timestamp,
                sampleRate: sampleRate,
                channelCount: channelCount
            )
        }

        var sumOfSquares: Float = 0
        var peak: Float = 0

        for sample in samples {
            let magnitude = abs(sample)
            sumOfSquares += sample * sample
            peak = max(peak, magnitude)
        }

        return AudioLevelSnapshot(
            rms: sqrt(sumOfSquares / Float(samples.count)),
            peak: peak,
            timestamp: timestamp,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }

    nonisolated static func snapshot(
        bufferList: UnsafePointer<AudioBufferList>,
        timestamp: Date = Date(),
        sampleRate: Double,
        channelCount: Int
    ) -> AudioLevelSnapshot {
        var sumOfSquares: Float = 0
        var peak: Float = 0
        var sampleCount = 0
        let bufferCount = Int(bufferList.pointee.mNumberBuffers)

        let firstBuffer = withUnsafePointer(to: bufferList.pointee.mBuffers) { pointer in
            UnsafeRawPointer(pointer).assumingMemoryBound(to: AudioBuffer.self)
        }

        for bufferIndex in 0..<bufferCount {
            let buffer = firstBuffer[bufferIndex]
            guard let data = buffer.mData else { continue }

            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.stride
            let samples = data.bindMemory(to: Float.self, capacity: count)

            for index in 0..<count {
                let sample = samples[index]
                let magnitude = abs(sample)
                sumOfSquares += sample * sample
                peak = max(peak, magnitude)
            }

            sampleCount += count
        }

        guard sampleCount > 0 else {
            return AudioLevelSnapshot(
                rms: 0,
                peak: 0,
                timestamp: timestamp,
                sampleRate: sampleRate,
                channelCount: channelCount
            )
        }

        return AudioLevelSnapshot(
            rms: sqrt(sumOfSquares / Float(sampleCount)),
            peak: peak,
            timestamp: timestamp,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }
}
