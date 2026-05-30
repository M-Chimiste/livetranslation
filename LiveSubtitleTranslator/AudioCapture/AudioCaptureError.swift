//
//  AudioCaptureError.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/20/26.
//

import CoreAudio
import Foundation

enum AudioCaptureError: Error, Equatable, LocalizedError, Sendable {
    case selectedAppCaptureUnavailable
    case sourceUnavailable
    case invalidAudioFormat
    case coreAudio(operation: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .selectedAppCaptureUnavailable:
            "Selected app capture is not wired yet. Choose System Output for Phase 4."
        case .sourceUnavailable:
            "The selected audio source is unavailable."
        case .invalidAudioFormat:
            "The capture stream format is not supported for level metering."
        case let .coreAudio(operation, status):
            "\(operation) failed with \(Self.describe(status: status))."
        }
    }

    static func describe(status: OSStatus) -> String {
        let code = fourCharacterCode(status)
        return code.isEmpty ? "OSStatus \(status)" : "OSStatus \(status) ('\(code)')"
    }

    private static func fourCharacterCode(_ status: OSStatus) -> String {
        let bigEndian = UInt32(bitPattern: status).bigEndian
        let bytes = [
            UInt8((bigEndian >> 24) & 0xff),
            UInt8((bigEndian >> 16) & 0xff),
            UInt8((bigEndian >> 8) & 0xff),
            UInt8(bigEndian & 0xff)
        ]

        guard bytes.allSatisfy({ byte in
            byte >= 32 && byte < 127
        }) else {
            return ""
        }

        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}
