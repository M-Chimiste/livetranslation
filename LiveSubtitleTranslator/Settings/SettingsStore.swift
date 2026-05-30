//
//  SettingsStore.swift
//  LiveSubtitleTranslator
//
//  Created by Christian Merrill on 5/20/26.
//

import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    private let userDefaults: UserDefaults
    private let storageKey: String

    @Published var settings: AppSettings {
        didSet {
            save(settings)
        }
    }

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "LiveSubtitleTranslator.AppSettings"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.settings = Self.loadSettings(from: userDefaults, key: storageKey)
    }

    func resetToDefaults() {
        settings = .defaults
    }

    private func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    private static func loadSettings(from userDefaults: UserDefaults, key: String) -> AppSettings {
        guard let data = userDefaults.data(forKey: key),
              let decodedSettings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return .defaults
        }

        return decodedSettings
    }
}
