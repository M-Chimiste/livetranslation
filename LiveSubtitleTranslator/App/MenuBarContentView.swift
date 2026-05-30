//
//  MenuBarContentView.swift
//  LiveSubtitleTranslator
//
//  Created by Christian Merrill on 5/20/26.
//

import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var subtitleCoordinator: SubtitleCoordinator
    @ObservedObject var overlayController: SubtitleOverlayWindowController
    @ObservedObject var liveSubtitleSessionController: LiveSubtitleSessionController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text("Pipeline: \(subtitleCoordinator.pipelineState.displayName)")
        Text("Live: \(liveSubtitleSessionController.state.displayName)")
        Text("Overlay: \(overlayController.isVisible ? "Visible" : "Hidden")")

        Divider()

        Button("Start Live Subtitles", systemImage: "dot.radiowaves.left.and.right") {
            Task {
                await liveSubtitleSessionController.start()
            }
        }
        .disabled(liveSubtitleSessionController.state.isActive)

        Button("Stop Live Subtitles", systemImage: "stop.fill") {
            Task {
                await liveSubtitleSessionController.stop()
            }
        }
        .disabled(!liveSubtitleSessionController.state.isActive)

        Divider()

        Button(overlayController.isVisible ? "Hide Overlay" : "Show Overlay", systemImage: "captions.bubble") {
            overlayController.toggleVisibility()
        }

        Button(settingsStore.settings.overlay.isLocked ? "Unlock Overlay" : "Lock Overlay", systemImage: settingsStore.settings.overlay.isLocked ? "lock.open" : "lock") {
            overlayController.toggleLocked()
        }

        Button("Reset Overlay Position", systemImage: "arrow.counterclockwise") {
            overlayController.resetFrame()
        }

        Divider()

        Button("Open Settings...", systemImage: "gearshape") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openSettings()
        }

        Button("Quit", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
    }
}
