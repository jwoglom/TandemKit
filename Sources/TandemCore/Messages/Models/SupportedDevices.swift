//
//  SupportedDevices.swift
//  TandemKit
//
//  Created by James Woglom on 1/7/25.
//
// https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/models/SupportedDevices.java


public enum KnownDeviceModel: String, Codable, Sendable {
    case tslimX2 = "t_slim_x2"
    case mobi = "mobi"
}

public extension KnownDeviceModel {
    var displayName: String {
        switch self {
        case .tslimX2:
            return "t:slim X2"
        case .mobi:
            return "t:Mobi"
        }
    }
}

public enum SupportedDevices: Sendable {
    case all
    case tslimX2Only
    case mobiOnly

    public var value: [KnownDeviceModel] {
        switch self {
        case .all:
            return [.tslimX2, .mobi]
        case .tslimX2Only:
            return [.tslimX2]
        case .mobiOnly:
            return [.mobi]
        }
    }
}
