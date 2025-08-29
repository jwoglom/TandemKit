//
//  CurrentBatteryV1.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of CurrentBatteryV1Request and CurrentBatteryV1Response based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/CurrentBatteryV1Request.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/CurrentBatteryV1Response.java
//

import Foundation

/// Request the current battery information (legacy API).
public class CurrentBatteryV1Request: Message {
    public static let props = MessageProps(
        opCode: 52,
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

/// Response with basic battery info for older API versions.
public class CurrentBatteryV1Response: Message {
    public static let props = MessageProps(
        opCode: 53,
        size: 2,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var currentBatteryAbc: Int
    public var currentBatteryIbc: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.currentBatteryAbc = Int(cargo[0])
        self.currentBatteryIbc = Int(cargo[1])
    }

    public init(currentBatteryAbc: Int, currentBatteryIbc: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(currentBatteryAbc),
            Bytes.firstByteLittleEndian(currentBatteryIbc)
        )
        self.currentBatteryAbc = currentBatteryAbc
        self.currentBatteryIbc = currentBatteryIbc
    }

    /// Convenience accessor mapping to battery percent used by the pump UI.
    public func getBatteryPercent() -> Int {
        return currentBatteryIbc
    }
}


extension CurrentBatteryV1Response: CurrentBatteryAbstractResponse {}
