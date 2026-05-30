//
//  AppSettings.swift
//  LiveSubtitleTranslator
//
//  Created by Christian Merrill on 5/20/26.
//

import CoreGraphics
import Foundation

struct AppSettings: Codable, Equatable {
    var audioSource: AudioSourceOption
    var asrBackend: ASRBackend
    var translationBackend: TranslationBackend
    var sourceLanguage: SubtitleLanguage
    var targetLanguage: SubtitleLanguage
    var latencyProfile: LatencyProfile
    var diagnosticsEnabled: Bool
    var remoteServerURL: URL?
    var overlay: OverlaySettings
    var voiceActivity: VoiceActivitySettings
    var localASR: LocalASRSettings

    static let defaults = AppSettings(
        audioSource: .systemOutput,
        asrBackend: .localWhisperKit,
        translationBackend: .appleTranslation,
        sourceLanguage: .english,
        targetLanguage: .simplifiedChinese,
        latencyProfile: .balanced,
        diagnosticsEnabled: true,
        remoteServerURL: nil,
        overlay: .defaults,
        voiceActivity: .defaults,
        localASR: .defaults
    )

    init(
        audioSource: AudioSourceOption,
        asrBackend: ASRBackend,
        translationBackend: TranslationBackend,
        sourceLanguage: SubtitleLanguage = .english,
        targetLanguage: SubtitleLanguage,
        latencyProfile: LatencyProfile,
        diagnosticsEnabled: Bool,
        remoteServerURL: URL?,
        overlay: OverlaySettings,
        voiceActivity: VoiceActivitySettings = .defaults,
        localASR: LocalASRSettings = .defaults
    ) {
        self.audioSource = audioSource
        self.asrBackend = asrBackend
        self.translationBackend = translationBackend
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.latencyProfile = latencyProfile
        self.diagnosticsEnabled = diagnosticsEnabled
        self.remoteServerURL = remoteServerURL
        self.overlay = overlay
        self.voiceActivity = voiceActivity
        self.localASR = localASR
    }

    private enum CodingKeys: String, CodingKey {
        case audioSource
        case asrBackend
        case translationBackend
        case sourceLanguage
        case targetLanguage
        case latencyProfile
        case diagnosticsEnabled
        case remoteServerURL
        case overlay
        case voiceActivity
        case localASR
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.audioSource = try container.decodeIfPresent(AudioSourceOption.self, forKey: .audioSource) ?? .systemOutput
        let decodedASRBackend = try container.decodeIfPresent(ASRBackend.self, forKey: .asrBackend) ?? .localWhisperKit
        let decodedTranslationBackend = try container.decodeIfPresent(TranslationBackend.self, forKey: .translationBackend) ?? .appleTranslation
        self.asrBackend = decodedASRBackend.userSelectableValue
        self.translationBackend = decodedTranslationBackend.userSelectableValue
        self.sourceLanguage = try container.decodeIfPresent(SubtitleLanguage.self, forKey: .sourceLanguage) ?? .english
        self.targetLanguage = try container.decodeIfPresent(SubtitleLanguage.self, forKey: .targetLanguage) ?? .simplifiedChinese
        self.latencyProfile = try container.decodeIfPresent(LatencyProfile.self, forKey: .latencyProfile) ?? .balanced
        self.diagnosticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .diagnosticsEnabled) ?? true
        self.remoteServerURL = try container.decodeIfPresent(URL.self, forKey: .remoteServerURL)
        self.overlay = try container.decodeIfPresent(OverlaySettings.self, forKey: .overlay) ?? .defaults
        self.voiceActivity = try container.decodeIfPresent(VoiceActivitySettings.self, forKey: .voiceActivity) ?? .defaults
        self.localASR = try container.decodeIfPresent(LocalASRSettings.self, forKey: .localASR) ?? .defaults
    }
}

struct LocalASRSettings: Codable, Equatable, Sendable {
    nonisolated static let tinyModelID = "openai_whisper-tiny"
    nonisolated static let largeV3ModelID = "openai_whisper-large-v3-v20240930_626MB"
    nonisolated static let largeV3TurboModelID = "openai_whisper-large-v3-v20240930_turbo_632MB"
    nonisolated static let legacyTinyModelID = "tiny"
    nonisolated static let legacyLargeV3ModelID = "large-v3-v20240930_626MB"
    nonisolated static let legacyLargeV3TurboModelID = "large-v3-v20240930_turbo_632MB"
    nonisolated static let availableModelIDs = [largeV3ModelID, largeV3TurboModelID, tinyModelID]
    nonisolated static let defaults = LocalASRSettings(modelID: largeV3ModelID)

    var modelID: String

    nonisolated init(modelID: String) {
        self.modelID = Self.canonicalModelID(for: modelID)
    }

    private enum CodingKeys: String, CodingKey {
        case modelID
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedModelID = try container.decodeIfPresent(String.self, forKey: .modelID) ?? Self.largeV3ModelID
        self.modelID = Self.canonicalModelID(for: decodedModelID)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelID, forKey: .modelID)
    }

    nonisolated static func canonicalModelID(for modelID: String) -> String {
        switch modelID {
        case legacyTinyModelID:
            tinyModelID
        case legacyLargeV3ModelID:
            largeV3ModelID
        case legacyLargeV3TurboModelID:
            largeV3TurboModelID
        default:
            modelID
        }
    }

    nonisolated static func displayName(for modelID: String) -> String {
        switch canonicalModelID(for: modelID) {
        case tinyModelID:
            "tiny"
        case largeV3ModelID:
            "large-v3-v20240930_626MB"
        case largeV3TurboModelID:
            "large-v3-v20240930_turbo_632MB"
        default:
            modelID
        }
    }
}

struct OverlaySettings: Codable, Equatable {
    var frame: OverlayFrame
    var isLocked: Bool

    static let defaults = OverlaySettings(
        frame: .defaults,
        isLocked: true
    )
}

struct OverlayFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let defaults = OverlayFrame(
        x: 120,
        y: 120,
        width: 1_200,
        height: 160
    )

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

enum AudioSourceOption: String, CaseIterable, Codable, Equatable, Identifiable {
    case systemOutput
    case selectedApp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .systemOutput:
            "System Output"
        case .selectedApp:
            "Selected App"
        }
    }
}

enum ASRBackend: String, CaseIterable, Codable, Equatable, Identifiable {
    case mock
    case localWhisperKit
    case remoteLAN

    static let userSelectableCases: [ASRBackend] = [.localWhisperKit, .remoteLAN]

    var id: String { rawValue }

    var userSelectableValue: ASRBackend {
        self == .mock ? .localWhisperKit : self
    }

    var displayName: String {
        switch self {
        case .mock:
            "Mock"
        case .localWhisperKit:
            "Local WhisperKit"
        case .remoteLAN:
            "Remote LAN"
        }
    }
}

enum TranslationBackend: String, CaseIterable, Codable, Equatable, Identifiable {
    case mock
    case appleTranslation
    case remoteLAN

    static let userSelectableCases: [TranslationBackend] = [.appleTranslation, .remoteLAN]

    var id: String { rawValue }

    var userSelectableValue: TranslationBackend {
        self == .mock ? .appleTranslation : self
    }

    var displayName: String {
        switch self {
        case .mock:
            "Mock"
        case .appleTranslation:
            "Apple Translation"
        case .remoteLAN:
            "Remote LAN"
        }
    }
}

struct SubtitleLanguage: Codable, Equatable, Hashable, Identifiable, Sendable {
    nonisolated static let english = SubtitleLanguage("en")
    nonisolated static let simplifiedChinese = SubtitleLanguage("zh-Hans")
    nonisolated static let traditionalChinese = SubtitleLanguage("zh-Hant")
    nonisolated static let fallbackCases: [SubtitleLanguage] = [.english, .simplifiedChinese, .traditionalChinese]

    let identifier: String

    nonisolated init(_ identifier: String) {
        self.identifier = Self.canonicalIdentifier(for: identifier)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identifier)
    }

    nonisolated var id: String { identifier }
    nonisolated var rawValue: String { identifier }

    nonisolated var displayName: String {
        if identifier == "en" {
            "English"
        } else if identifier == "zh-Hans" {
            "Simplified Chinese"
        } else if identifier == "zh-Hant" {
            "Traditional Chinese"
        } else {
            Locale.current.localizedString(forIdentifier: identifier) ?? identifier
        }
    }

    nonisolated var whisperLanguageCode: String {
        Locale.Language(identifier: identifier).languageCode?.identifier
            ?? identifier.split(separator: "-").first.map(String.init)
            ?? identifier
    }

    private nonisolated static func canonicalIdentifier(for identifier: String) -> String {
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)

        switch trimmedIdentifier.lowercased() {
        case "":
            return "en"
        case "zh", "zh-hans", "zh-cn", "zh-sg":
            return "zh-Hans"
        case "zh-hant", "zh-tw", "zh-hk", "zh-mo":
            return "zh-Hant"
        default:
            return trimmedIdentifier
        }
    }
}

enum LatencyProfile: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case fast
    case balanced
    case moreAccurate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fast:
            "Fast"
        case .balanced:
            "Balanced"
        case .moreAccurate:
            "More Accurate"
        }
    }
}
