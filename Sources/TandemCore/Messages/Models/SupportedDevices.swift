//
//  SupportedDevices.swift
//  TandemKit
//
//  Created by James Woglom on 1/7/25.
//
// https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/models/SupportedDevices.java


public enum KnownDeviceModel: Sendable {
    case tslimX2
    case mobi
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
