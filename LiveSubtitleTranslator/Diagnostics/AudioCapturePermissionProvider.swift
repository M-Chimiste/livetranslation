//
//  AudioCapturePermissionProvider.swift
//  LiveSubtitleTranslator
//
//  Created by Codex on 5/21/26.
//

import Darwin
import Foundation

protocol AudioCapturePermissionProviding: AnyObject {
    func currentStatus() -> AudioCapturePermissionStatus
    func requestPermission() async -> AudioCapturePermissionStatus
}

final class StaticAudioCapturePermissionProvider: AudioCapturePermissionProviding {
    private let status: AudioCapturePermissionStatus

    init(status: AudioCapturePermissionStatus) {
        self.status = status
    }

    func currentStatus() -> AudioCapturePermissionStatus {
        status
    }

    func requestPermission() async -> AudioCapturePermissionStatus {
        status
    }
}

final class SystemAudioCapturePermissionProvider: AudioCapturePermissionProviding {
    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int32
    private typealias RequestFunction = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    private static let serviceName = "kTCCServiceAudioCapture" as CFString
    private static let frameworkPath = "/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC"

    private nonisolated(unsafe) static let apiHandle: UnsafeMutableRawPointer? = {
        dlopen(frameworkPath, RTLD_NOW)
    }()

    func currentStatus() -> AudioCapturePermissionStatus {
        guard let preflight = Self.symbol(named: "TCCAccessPreflight", as: PreflightFunction.self) else {
            return .unknown
        }

        let result = preflight(Self.serviceName, nil)
        switch result {
        case 0:
            return .authorized
        case 1:
            return .denied
        default:
            return .notRequested
        }
    }

    func requestPermission() async -> AudioCapturePermissionStatus {
        guard let request = Self.symbol(named: "TCCAccessRequest", as: RequestFunction.self) else {
            return .unknown
        }

        return await withCheckedContinuation { continuation in
            request(Self.serviceName, nil) { granted in
                continuation.resume(returning: granted ? .authorized : .denied)
            }
        }
    }

    private static func symbol<T>(named symbolName: String, as type: T.Type) -> T? {
        guard let apiHandle,
              let symbol = dlsym(apiHandle, symbolName)
        else {
            return nil
        }

        return unsafeBitCast(symbol, to: type)
    }
}
