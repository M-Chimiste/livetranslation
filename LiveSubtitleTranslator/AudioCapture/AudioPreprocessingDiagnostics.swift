//
//  AudioPreprocessingDiagnostics.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import Foundation

struct AudioPreprocessingDiagnostics: Equatable, Sendable {
    var emittedChunkCount: Int
    var lastChunkDuration: TimeInterval?
    var queueDepthFrames: Int
    var droppedFrames: Int
    var callbackCount: Int
    var capturedFrameCount: Int

    nonisolated static let zero = AudioPreprocessingDiagnostics(
        emittedChunkCount: 0,
        lastChunkDuration: nil,
        queueDepthFrames: 0,
        droppedFrames: 0,
        callbackCount: 0,
        capturedFrameCount: 0
    )

    nonisolated init(
        emittedChunkCount: Int,
        lastChunkDuration: TimeInterval?,
        queueDepthFrames: Int,
        droppedFrames: Int,
        callbackCount: Int = 0,
        capturedFrameCount: Int = 0
    ) {
        self.emittedChunkCount = emittedChunkCount
        self.lastChunkDuration = lastChunkDuration
        self.queueDepthFrames = queueDepthFrames
        self.droppedFrames = droppedFrames
        self.callbackCount = callbackCount
        self.capturedFrameCount = capturedFrameCount
    }

    var emittedChunkCountDisplayValue: String {
        "\(emittedChunkCount)"
    }

    var lastChunkDurationDisplayValue: String {
        guard let lastChunkDuration else { return "None" }
        return String(format: "%.2f s", lastChunkDuration)
    }

    var queueDepthDisplayValue: String {
        "\(queueDepthFrames)"
    }

    var droppedFramesDisplayValue: String {
        "\(droppedFrames)"
    }

    var callbackCountDisplayValue: String {
        "\(callbackCount)"
    }

    var capturedFrameCountDisplayValue: String {
        "\(capturedFrameCount)"
    }
}
