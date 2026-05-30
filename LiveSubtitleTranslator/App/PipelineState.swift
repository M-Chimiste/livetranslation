//
//  PipelineState.swift
//  LiveSubtitleTranslator
//
//  Created by Christian Merrill on 5/20/26.
//

enum PipelineState: String, Codable, Equatable {
    case idle
    case listening
    case transcribing
    case translating
    case error

    var displayName: String {
        switch self {
        case .idle:
            "Idle"
        case .listening:
            "Listening"
        case .transcribing:
            "Transcribing"
        case .translating:
            "Translating"
        case .error:
            "Error"
        }
    }

    var isRunning: Bool {
        self != .idle && self != .error
    }
}
