//
//  KnownApiVersion.swift
//  TandemKit
//
//  Created by James Woglom on 1/7/25.
//
// https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/models/KnownApiVersion.java

/// Represents an API version with major and minor components.
public struct ApiVersion: Sendable {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }
}

/// Known API versions
public enum KnownApiVersion: Sendable {
    /// v2.1 is the API version used by software v7.1 and v7.4.
    case apiV2_1

    /// v2.5 is the API version used by software v7.6 and includes remote bolus.
    case apiV2_5

    /// v3.2 is the API version used by software v7.7 (6-digit numeric pairing PIN).
    case apiV3_2

    /// v3.4 is the API version used by software v7.8.
    case apiV3_4

    /// Tandem Mobi initial release.
    case mobiApiV3_5

    /// Future API messages that cannot be parsed with known firmware.
    case apiFuture

    /// Returns the `ApiVersion` corresponding to each case.
    var value: ApiVersion {
        switch self {
        case .apiV2_1:
            return ApiVersion(major: 2, minor: 1)
        case .apiV2_5:
            return ApiVersion(major: 2, minor: 5)
        case .apiV3_2:
            return ApiVersion(major: 3, minor: 2)
        case .apiV3_4:
            return ApiVersion(major: 3, minor: 4)
        case .mobiApiV3_5:
            return ApiVersion(major: 3, minor: 5)
        case .apiFuture:
            return ApiVersion(major: 99, minor: 99)
        }
    }
}

extension ApiVersion {
    public func greaterThan(_ other: ApiVersion) -> Bool {
        return major > other.major || (major == other.major && minor > other.minor)
    }

    public func greaterThan(_ other: KnownApiVersion) -> Bool {
        return greaterThan(other.value)
    }

    public func serialize() -> String {
        return "\(major),\(minor)"
    }

    public static func deserialize(_ s: String?) -> ApiVersion? {
        guard let s = s, !s.isEmpty else { return nil }
        let parts = s.split(separator: ",")
        guard parts.count == 2,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else {
            return nil
        }
        return ApiVersion(major: major, minor: minor)
    }
}
