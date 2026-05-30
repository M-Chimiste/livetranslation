//
//  WhisperKitModelCatalog.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/22/26.
//

import Combine
import Foundation
import WhisperKit

struct WhisperKitModelCatalogSnapshot: Equatable, Sendable {
    let defaultModelID: String
    let supportedModelIDs: [String]
    let disabledModelIDs: [String]

    init(
        defaultModelID: String,
        supportedModelIDs: [String],
        disabledModelIDs: [String] = []
    ) {
        self.defaultModelID = LocalASRSettings.canonicalModelID(for: defaultModelID)
        self.supportedModelIDs = supportedModelIDs.map(LocalASRSettings.canonicalModelID(for:))
        self.disabledModelIDs = disabledModelIDs.map(LocalASRSettings.canonicalModelID(for:))
    }

    init(_ support: ModelSupport) {
        self.init(
            defaultModelID: support.default,
            supportedModelIDs: support.supported,
            disabledModelIDs: support.disabled
        )
    }
}

protocol WhisperKitModelProviding {
    func localModelSupport() -> WhisperKitModelCatalogSnapshot
    func remoteModelSupport() async -> WhisperKitModelCatalogSnapshot
}

struct LiveWhisperKitModelProvider: WhisperKitModelProviding {
    nonisolated init() {}

    func localModelSupport() -> WhisperKitModelCatalogSnapshot {
        WhisperKitModelCatalogSnapshot(WhisperKit.recommendedModels())
    }

    func remoteModelSupport() async -> WhisperKitModelCatalogSnapshot {
        let support = await WhisperKit.recommendedRemoteModels()
        return WhisperKitModelCatalogSnapshot(support)
    }
}

@MainActor
final class WhisperKitModelCatalog: ObservableObject {
    @Published private(set) var modelIDs: [String]
    @Published private(set) var isRefreshing = false

    private let provider: WhisperKitModelProviding

    init(
        selectedModelID: String = LocalASRSettings.defaults.modelID,
        provider: WhisperKitModelProviding = LiveWhisperKitModelProvider()
    ) {
        self.provider = provider
        let localSupport = provider.localModelSupport()
        self.modelIDs = Self.visibleModelIDs(
            supportedModelIDs: localSupport.supportedModelIDs,
            disabledModelIDs: localSupport.disabledModelIDs,
            selectedModelID: selectedModelID
        )
    }

    func refresh(selectedModelID: String) async {
        isRefreshing = true
        defer { isRefreshing = false }

        let remoteSupport = await provider.remoteModelSupport()
        modelIDs = Self.visibleModelIDs(
            supportedModelIDs: modelIDs + remoteSupport.supportedModelIDs,
            disabledModelIDs: remoteSupport.disabledModelIDs,
            selectedModelID: selectedModelID
        )
    }

    static func visibleModelIDs(
        supportedModelIDs: [String],
        disabledModelIDs: [String],
        selectedModelID: String
    ) -> [String] {
        let selectedModelID = LocalASRSettings.canonicalModelID(for: selectedModelID)
        let disabledModelIDSet = Set(disabledModelIDs.map(LocalASRSettings.canonicalModelID(for:)))
        let supportedModelIDs = supportedModelIDs
            .map(LocalASRSettings.canonicalModelID(for:))
            .filter { !disabledModelIDSet.contains($0) || $0 == selectedModelID }
        let supportedModelIDSet = Set(supportedModelIDs)
        let prioritizedModelIDs = [
            LocalASRSettings.largeV3ModelID,
            LocalASRSettings.largeV3TurboModelID,
            LocalASRSettings.tinyModelID
        ].filter { supportedModelIDSet.contains($0) || $0 == selectedModelID }

        return orderedUnique(
            [selectedModelID] + prioritizedModelIDs + supportedModelIDs
        )
    }

    private static func orderedUnique(_ modelIDs: [String]) -> [String] {
        var seenModelIDs = Set<String>()
        var uniqueModelIDs: [String] = []

        for modelID in modelIDs where seenModelIDs.insert(modelID).inserted {
            uniqueModelIDs.append(modelID)
        }

        return uniqueModelIDs
    }
}
