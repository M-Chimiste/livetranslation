//
//  MockSubtitleTicker.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import Combine
import Foundation

@MainActor
final class MockSubtitleTicker: ObservableObject {
    static let defaultLines = [
        "我们今晚要去哪里？",
        "我不知道，但先离开这里。",
        "这不是一个好主意。",
        "等等，我听到有人来了。"
    ]

    private let displayModel: SubtitleDisplayModel
    private let lines: [String]
    private let interval: Duration
    private var task: Task<Void, Never>?
    private var nextLineIndex = 0

    @Published private(set) var isRunning = false

    init(
        displayModel: SubtitleDisplayModel,
        lines: [String]? = nil,
        interval: Duration = .seconds(3)
    ) {
        self.displayModel = displayModel
        self.lines = lines ?? Self.defaultLines
        self.interval = interval
    }

    deinit {
        task?.cancel()
    }

    func start() {
        guard !isRunning else { return }

        isRunning = true
        emitNext()

        let interval = self.interval
        task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }

                await MainActor.run {
                    self?.emitNext()
                }
            }
        }
    }

    func stop() {
        guard isRunning || task != nil else {
            displayModel.clear()
            return
        }

        task?.cancel()
        task = nil
        isRunning = false
        displayModel.clear()
    }

    func emitNext() {
        guard !lines.isEmpty else {
            displayModel.clear()
            return
        }

        let line = lines[nextLineIndex % lines.count]
        nextLineIndex += 1

        displayModel.update(
            SubtitleDisplayState(primaryLine: line)
        )
    }
}
