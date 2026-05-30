//
//  MockPipelineController.swift
//  LiveSubtitleTranslator
//
//  Created by Christian Merrill on 5/20/26.
//

import Combine

@MainActor
final class MockPipelineController: ObservableObject {
    @Published private(set) var state: PipelineState = .idle

    func start() {
        guard state == .idle else { return }
        state = .listening
    }

    func stop() {
        guard state != .idle else { return }
        state = .idle
    }
}
