//
//  AudioResampler.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

@preconcurrency import AVFoundation
import Foundation

enum AudioResamplerError: Error, Equatable, LocalizedError, Sendable {
    case invalidFormat
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            "The audio resampler could not create the requested PCM format."
        case let .conversionFailed(message):
            "Audio resampling failed: \(message)"
        }
    }
}

struct AudioResampler: Sendable {
    let sourceSampleRate: Double
    let sourceChannelCount: Int
    let targetSampleRate: Double
    let targetChannelCount: Int

    nonisolated init(
        sourceSampleRate: Double,
        sourceChannelCount: Int,
        targetSampleRate: Double = 16_000,
        targetChannelCount: Int = 1
    ) {
        self.sourceSampleRate = sourceSampleRate
        self.sourceChannelCount = max(1, sourceChannelCount)
        self.targetSampleRate = targetSampleRate
        self.targetChannelCount = max(1, targetChannelCount)
    }

    nonisolated func convert(interleavedSamples samples: [Float]) throws -> [Float] {
        guard !samples.isEmpty else { return [] }

        let monoSamples = mixDownToMono(interleavedSamples: samples)
        guard sourceSampleRate != targetSampleRate else {
            return monoSamples
        }

        let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceSampleRate,
            channels: 1,
            interleaved: false
        )
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: AVAudioChannelCount(targetChannelCount),
            interleaved: false
        )
        guard let sourceFormat, let targetFormat else {
            throw AudioResamplerError.invalidFormat
        }

        let inputFrameCount = monoSamples.count
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(inputFrameCount)
        ) else {
            throw AudioResamplerError.invalidFormat
        }

        inputBuffer.frameLength = AVAudioFrameCount(inputFrameCount)
        if let channelData = inputBuffer.floatChannelData {
            for index in 0..<inputFrameCount {
                channelData[0][index] = monoSamples[index]
            }
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioResamplerError.invalidFormat
        }
        converter.primeMethod = .none

        let expectedOutputFrames = Int(
            (Double(inputFrameCount) * targetSampleRate / sourceSampleRate).rounded()
        )
        let outputCapacity = AVAudioFrameCount(max(1, expectedOutputFrames + 512))
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputCapacity
        ) else {
            throw AudioResamplerError.invalidFormat
        }

        var consumedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if consumedInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            consumedInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let conversionError {
            throw AudioResamplerError.conversionFailed(conversionError.localizedDescription)
        }
        guard status != .error else {
            throw AudioResamplerError.conversionFailed("Unknown converter error")
        }

        let outputFrameCount = Int(outputBuffer.frameLength)
        guard outputFrameCount > 0, let channelData = outputBuffer.floatChannelData else {
            return []
        }

        var outputSamples = Array(repeating: Float(0), count: outputFrameCount)
        for index in 0..<outputFrameCount {
            outputSamples[index] = channelData[0][index]
        }

        if outputSamples.count > expectedOutputFrames {
            outputSamples.removeLast(outputSamples.count - expectedOutputFrames)
        } else if outputSamples.count < expectedOutputFrames {
            outputSamples.append(
                contentsOf: repeatElement(0, count: expectedOutputFrames - outputSamples.count)
            )
        }

        return outputSamples
    }

    private nonisolated func mixDownToMono(interleavedSamples samples: [Float]) -> [Float] {
        let frameCount = samples.count / sourceChannelCount
        guard frameCount > 0 else { return [] }
        guard sourceChannelCount > 1 else {
            return Array(samples.prefix(frameCount))
        }

        var monoSamples = Array(repeating: Float(0), count: frameCount)

        for frame in 0..<frameCount {
            var sum: Float = 0
            let frameStart = frame * sourceChannelCount

            for channel in 0..<sourceChannelCount {
                sum += samples[frameStart + channel]
            }

            monoSamples[frame] = sum / Float(sourceChannelCount)
        }

        return monoSamples
    }
}
