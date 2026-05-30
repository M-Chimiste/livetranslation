//
//  ASRDiagnostics.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/21/26.
//

import Foundation

enum ASRDiagnosticsLifecycleState: String, Equatable, Sendable {
    case idle
    case loading
    case ready
    case transcribing
    case error

    var displayName: String {
        switch self {
        case .idle:
            "Idle"
        case .loading:
            "Loading"
        case .ready:
            "Ready"
        case .transcribing:
            "Transcribing"
        case .error:
            "Error"
        }
    }
}

struct ASRDiagnosticsState: Equatable, Sendable {
    var lifecycleState: ASRDiagnosticsLifecycleState
    var backend: ASRBackend
    var modelID: String
    var acceptedSpeechChunkCount: Int
    var completedTranscriptCount: Int
    var lastTranscript: String?
    var lastErrorMessage: String?

    nonisolated static let placeholder = ASRDiagnosticsState(
        lifecycleState: .idle,
        backend: .mock,
        modelID: LocalASRSettings.defaults.modelID,
        acceptedSpeechChunkCount: 0,
        completedTranscriptCount: 0,
        lastTranscript: nil,
        lastErrorMessage: nil
    )

    nonisolated init(
        lifecycleState: ASRDiagnosticsLifecycleState,
        backend: ASRBackend,
        modelID: String,
        acceptedSpeechChunkCount: Int = 0,
        completedTranscriptCount: Int = 0,
        lastTranscript: String? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.lifecycleState = lifecycleState
        self.backend = backend
        self.modelID = modelID
        self.acceptedSpeechChunkCount = acceptedSpeechChunkCount
        self.completedTranscriptCount = completedTranscriptCount
        self.lastTranscript = lastTranscript
        self.lastErrorMessage = lastErrorMessage
    }

    var lifecycleStateDisplayValue: String {
        lifecycleState.displayName
    }

    var backendDisplayValue: String {
        backend.displayName
    }

    var acceptedSpeechChunkCountDisplayValue: String {
        "\(acceptedSpeechChunkCount)"
    }

    var completedTranscriptCountDisplayValue: String {
        "\(completedTranscriptCount)"
    }

    var lastTranscriptDisplayValue: String {
        lastTranscript ?? "None"
    }

    nonisolated static func idle(
        backend: ASRBackend,
        modelID: String
    ) -> ASRDiagnosticsState {
        ASRDiagnosticsState(
            lifecycleState: .idle,
            backend: backend,
            modelID: modelID
        )
    }
}
