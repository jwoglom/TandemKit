//
//  CurrentBasalStatus.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of CurrentBasalStatusRequest and CurrentBasalStatusResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/CurrentBasalStatusRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/CurrentBasalStatusResponse.java
//

import Foundation

/// Request information about the current basal delivery rate.
public class CurrentBasalStatusRequest: Message {
    public static var props = MessageProps(
        opCode: 40,
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

/// Response describing the basal profile rate and current delivery rate.
public class CurrentBasalStatusResponse: Message {
    public static var props = MessageProps(
        opCode: 41,
        size: 9,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var profileBasalRate: UInt32
    public var currentBasalRate: UInt32
    public var basalModifiedBitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.profileBasalRate = Bytes.readUint32(cargo, 0)
        self.currentBasalRate = Bytes.readUint32(cargo, 4)
        self.basalModifiedBitmask = Int(cargo[8])
    }

    public init(profileBasalRate: UInt32, currentBasalRate: UInt32, basalModifiedBitmask: Int) {
        self.cargo = Bytes.combine(
            Bytes.toUint32(profileBasalRate),
            Bytes.toUint32(currentBasalRate),
            Bytes.firstByteLittleEndian(basalModifiedBitmask)
        )
        self.profileBasalRate = profileBasalRate
        self.currentBasalRate = currentBasalRate
        self.basalModifiedBitmask = basalModifiedBitmask
    }
}

