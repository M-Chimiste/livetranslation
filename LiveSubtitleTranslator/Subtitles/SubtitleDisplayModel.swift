//
//  SubtitleDisplayModel.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import Combine

enum SubtitleOverlayStatus: Equatable, Sendable {
    case preparingLiveSubtitles
    case listening
    case error

    var displayText: String {
        switch self {
        case .preparingLiveSubtitles:
            "准备字幕…"
        case .listening:
            "正在听取英文音频…"
        case .error:
            "字幕暂不可用"
        }
    }
}

@MainActor
final class SubtitleDisplayModel: ObservableObject {
    @Published private(set) var displayState: SubtitleDisplayState?
    @Published private(set) var overlayStatus: SubtitleOverlayStatus?

    func update(_ displayState: SubtitleDisplayState) {
        self.displayState = displayState
        overlayStatus = nil
    }

    func showStatus(_ overlayStatus: SubtitleOverlayStatus) {
        guard displayState == nil else { return }
        self.overlayStatus = overlayStatus
    }

    func clearStatus() {
        overlayStatus = nil
    }

    func clear() {
        displayState = nil
        overlayStatus = nil
    }
}
