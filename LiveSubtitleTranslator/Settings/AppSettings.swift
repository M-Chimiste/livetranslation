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
        asrBackend: .localParakeet,
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
        let decodedASRBackend = try container.decodeIfPresent(ASRBackend.self, forKey: .asrBackend) ?? .localParakeet
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
    // Parakeet (FluidAudio) model versions. v3 is multilingual (auto-detects the
    // 25 supported European languages incl. English); v2 is English-only.
    nonisolated static let parakeetV3ModelID = "parakeet-tdt-0.6b-v3"
    nonisolated static let parakeetV2ModelID = "parakeet-tdt-0.6b-v2"
    nonisolated static let availableModelIDs = [parakeetV3ModelID, parakeetV2ModelID]

    // WhisperKit model IDs (selectable alternative backend).
    nonisolated static let whisperTinyModelID = "openai_whisper-tiny"
    nonisolated static let whisperLargeV3ModelID = "openai_whisper-large-v3-v20240930_626MB"
    nonisolated static let whisperLargeV3TurboModelID = "openai_whisper-large-v3-v20240930_turbo_632MB"
    nonisolated static let whisperKitModelIDs = [whisperLargeV3ModelID, whisperLargeV3TurboModelID, whisperTinyModelID]

    nonisolated static let defaults = LocalASRSettings(
        modelID: parakeetV3ModelID,
        whisperKitModelID: whisperLargeV3ModelID
    )

    /// The selected Parakeet model (kept as `modelID` for backward-compatible decoding).
    var modelID: String
    /// The selected WhisperKit model.
    var whisperKitModelID: String

    nonisolated init(modelID: String, whisperKitModelID: String = whisperLargeV3ModelID) {
        self.modelID = Self.canonicalModelID(for: modelID)
        self.whisperKitModelID = Self.canonicalWhisperKitModelID(for: whisperKitModelID)
    }

    private enum CodingKeys: String, CodingKey {
        case modelID
        case whisperKitModelID
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedModelID = try container.decodeIfPresent(String.self, forKey: .modelID) ?? Self.parakeetV3ModelID
        let decodedWhisperKitModelID = try container.decodeIfPresent(String.self, forKey: .whisperKitModelID) ?? Self.whisperLargeV3ModelID
        self.modelID = Self.canonicalModelID(for: decodedModelID)
        self.whisperKitModelID = Self.canonicalWhisperKitModelID(for: decodedWhisperKitModelID)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(whisperKitModelID, forKey: .whisperKitModelID)
    }

    /// The model ID for the given ASR backend (Parakeet vs WhisperKit have separate selections).
    nonisolated func activeModelID(for backend: ASRBackend) -> String {
        backend == .localWhisperKit ? whisperKitModelID : modelID
    }

    /// Canonical Parakeet ID. Legacy WhisperKit IDs (from before the Parakeet
    /// migration, when this single field stored a Whisper model) collapse to the
    /// v3 default so existing persisted *Parakeet* selections keep working.
    nonisolated static func canonicalModelID(for modelID: String) -> String {
        switch modelID {
        case parakeetV2ModelID:
            return parakeetV2ModelID
        case parakeetV3ModelID:
            return parakeetV3ModelID
        default:
            return parakeetV3ModelID
        }
    }

    /// Canonical WhisperKit ID; maps legacy unnamespaced names to the namespaced
    /// model IDs and falls back to large-v3.
    nonisolated static func canonicalWhisperKitModelID(for modelID: String) -> String {
        switch modelID {
        case whisperTinyModelID, "tiny":
            return whisperTinyModelID
        case whisperLargeV3ModelID, "large-v3-v20240930_626MB":
            return whisperLargeV3ModelID
        case whisperLargeV3TurboModelID, "large-v3-v20240930_turbo_632MB":
            return whisperLargeV3TurboModelID
        default:
            return whisperLargeV3ModelID
        }
    }

    nonisolated static func displayName(for modelID: String) -> String {
        switch canonicalModelID(for: modelID) {
        case parakeetV2ModelID:
            return "Parakeet v2 (English)"
        case parakeetV3ModelID:
            return "Parakeet v3 (multilingual)"
        default:
            return modelID
        }
    }

    nonisolated static func whisperKitDisplayName(for modelID: String) -> String {
        switch canonicalWhisperKitModelID(for: modelID) {
        case whisperTinyModelID:
            return "Whisper tiny"
        case whisperLargeV3ModelID:
            return "Whisper large-v3"
        case whisperLargeV3TurboModelID:
            return "Whisper large-v3 turbo"
        default:
            return modelID
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
    case localParakeet
    case localWhisperKit
    case remoteLAN

    static let userSelectableCases: [ASRBackend] = [.localParakeet, .localWhisperKit, .remoteLAN]

    var id: String { rawValue }

    var userSelectableValue: ASRBackend {
        self == .mock ? .localParakeet : self
    }

    /// Custom decode so any unknown value falls back to the default local backend
    /// rather than throwing.
    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case ASRBackend.mock.rawValue:
            self = .mock
        case ASRBackend.localWhisperKit.rawValue:
            self = .localWhisperKit
        case ASRBackend.remoteLAN.rawValue:
            self = .remoteLAN
        case ASRBackend.localParakeet.rawValue:
            self = .localParakeet
        default:
            self = .localParakeet
        }
    }

    var displayName: String {
        switch self {
        case .mock:
            "Mock"
        case .localParakeet:
            "Local Parakeet"
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
    case localNLLB
    case localHunyuanMT
    case remoteLAN

    static let userSelectableCases: [TranslationBackend] = [.appleTranslation, .localNLLB, .localHunyuanMT, .remoteLAN]

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
        case .localNLLB:
            "Local NLLB"
        case .localHunyuanMT:
            "Local Hunyuan-MT"
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
