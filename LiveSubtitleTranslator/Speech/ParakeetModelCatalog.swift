//
//  ParakeetModelCatalog.swift
//  LiveSubtitleTranslator
//
//  Parakeet (FluidAudio) exposes a small fixed set of model versions rather
//  than a downloadable catalog, so this is a thin list source for the Settings
//  picker. It keeps the same shape (`modelIDs` / `isRefreshing` / `refresh`) the
//  former WhisperKit catalog exposed so the view bindings are unchanged.
//

import Combine
import Foundation

@MainActor
final class ParakeetModelCatalog: ObservableObject {
    @Published private(set) var modelIDs: [String]
    @Published private(set) var isRefreshing = false

    init(selectedModelID: String = LocalASRSettings.defaults.modelID) {
        self.modelIDs = Self.visibleModelIDs(selectedModelID: selectedModelID)
    }

    /// No remote enumeration is needed for Parakeet; the available versions are
    /// fixed. Kept async + same signature so existing call sites are untouched.
    func refresh(selectedModelID: String) async {
        modelIDs = Self.visibleModelIDs(selectedModelID: selectedModelID)
    }

    static func visibleModelIDs(selectedModelID: String) -> [String] {
        let canonicalSelected = LocalASRSettings.canonicalModelID(for: selectedModelID)
        var ordered = LocalASRSettings.availableModelIDs
        if !ordered.contains(canonicalSelected) {
            ordered.insert(canonicalSelected, at: 0)
        }
        return ordered
    }
}
