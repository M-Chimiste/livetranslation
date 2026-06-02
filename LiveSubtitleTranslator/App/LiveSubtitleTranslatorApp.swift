//
//  LiveSubtitleTranslatorApp.swift
//  LiveSubtitleTranslator
//
//  Created by Christian Merrill on 5/20/26.
//

import SwiftUI

@main
struct LiveSubtitleTranslatorApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                settingsStore: appState.settingsStore,
                subtitleCoordinator: appState.subtitleCoordinator,
                overlayController: appState.overlayController,
                liveSubtitleSessionController: appState.liveSubtitleSessionController
            )
        } label: {
            Label("Live Subtitle Translator", systemImage: "captions.bubble")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                settingsStore: appState.settingsStore,
                subtitleCoordinator: appState.subtitleCoordinator,
                overlayController: appState.overlayController,
                audioDiagnosticsModel: appState.audioDiagnosticsModel,
                liveSubtitleSessionController: appState.liveSubtitleSessionController,
                translationLanguageCatalog: appState.translationLanguageCatalog,
                parakeetModelCatalog: appState.parakeetModelCatalog,
                nllbTranslationService: appState.nllbTranslationService,
                hunyuanTranslationService: appState.hunyuanTranslationService
            )
        }
    }
}
