//
//  MetricsRecorder.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import Combine
import Foundation

enum MetricsStage: String, Equatable, Sendable {
    case asrPartialReceived
    case asrFinalReceived
    case translationStarted
    case translationFinished
    case overlayRendered
    case errorReceived
}

struct MetricsEvent: Equatable, Sendable {
    let segmentID: UUID
    let stage: MetricsStage
    let timestamp: Date
}

@MainActor
final class MetricsRecorder: ObservableObject {
    @Published private(set) var events: [MetricsEvent] = []

    func record(
        _ stage: MetricsStage,
        segmentID: UUID,
        at timestamp: Date = Date()
    ) {
        events.append(
            MetricsEvent(
                segmentID: segmentID,
                stage: stage,
                timestamp: timestamp
            )
        )
    }

    func events(for segmentID: UUID) -> [MetricsEvent] {
        events.filter { $0.segmentID == segmentID }
    }

    func reset() {
        events.removeAll()
    }
}
