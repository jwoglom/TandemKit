//
//  PumpSettings.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of PumpSettingsRequest and PumpSettingsResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/PumpSettingsRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/PumpSettingsResponse.java
//

import Foundation

/// Request pump configuration settings.
public class PumpSettingsRequest: Message {
    public static var props = MessageProps(
        opCode: 82,
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}

/// Response with basic pump settings and status information.
public class PumpSettingsResponse: Message {
    public static var props = MessageProps(
        opCode: 83,
        size: 9,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var lowInsulinThreshold: Int
    public var cannulaPrimeSize: Int
    public var autoShutdownEnabled: Int
    public var autoShutdownDuration: Int
    public var featureLock: Int
    public var oledTimeout: Int
    public var status: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.lowInsulinThreshold = Int(cargo[0])
        self.cannulaPrimeSize = Int(cargo[1])
        self.autoShutdownEnabled = Int(cargo[2])
        self.autoShutdownDuration = Bytes.readShort(cargo, 3)
        self.featureLock = Int(cargo[5])
        self.oledTimeout = Int(cargo[6])
        self.status = Bytes.readShort(cargo, 7)
    }

    public init(lowInsulinThreshold: Int, cannulaPrimeSize: Int, autoShutdownEnabled: Int, autoShutdownDuration: Int, featureLock: Int, oledTimeout: Int, status: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(lowInsulinThreshold),
            Bytes.firstByteLittleEndian(cannulaPrimeSize),
            Bytes.firstByteLittleEndian(autoShutdownEnabled),
            Bytes.firstTwoBytesLittleEndian(autoShutdownDuration),
            Bytes.firstByteLittleEndian(featureLock),
            Bytes.firstByteLittleEndian(oledTimeout),
            Bytes.firstTwoBytesLittleEndian(status)
        )
        self.lowInsulinThreshold = lowInsulinThreshold
        self.cannulaPrimeSize = cannulaPrimeSize
        self.autoShutdownEnabled = autoShutdownEnabled
        self.autoShutdownDuration = autoShutdownDuration
        self.featureLock = featureLock
        self.oledTimeout = oledTimeout
        self.status = status
    }
}
