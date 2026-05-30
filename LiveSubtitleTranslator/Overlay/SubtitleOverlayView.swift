//
//  SubtitleOverlayView.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import SwiftUI

struct SubtitleOverlayView: View {
    @ObservedObject var displayModel: SubtitleDisplayModel
    @ObservedObject var settingsStore: SettingsStore

    private var isLocked: Bool {
        settingsStore.settings.overlay.isLocked
    }

    var body: some View {
        ZStack {
            if let displayState = displayModel.displayState {
                subtitleBackground

                VStack(spacing: 6) {
                    subtitleText(displayState.primaryLine)

                    if let secondaryLine = displayState.secondaryLine {
                        subtitleText(secondaryLine)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
            } else if let overlayStatus = displayModel.overlayStatus {
                subtitleBackground

                Text(overlayStatus.displayText)
                    .font(.system(size: 24, weight: .medium, design: .default))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }

            if !isLocked {
                editChrome
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
    }

    private var subtitleBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black.opacity(0.58))
            .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 3)
    }

    private var editChrome: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.cyan.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [8, 5]))

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.black.opacity(0.72))
                )
                .padding(8)
        }
    }

    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 42, weight: .semibold, design: .default))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.68)
            .shadow(color: .black.opacity(0.95), radius: 3, x: 0, y: 2)
            .shadow(color: .black.opacity(0.75), radius: 1, x: 0, y: 0)
    }
}
