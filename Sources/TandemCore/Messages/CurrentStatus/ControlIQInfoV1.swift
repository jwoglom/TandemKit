//
//  ControlIQInfoV1.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of ControlIQInfoV1Request and ControlIQInfoV1Response based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/ControlIQInfoV1Request.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/ControlIQInfoV1Response.java
//

import Foundation

/// Request Control-IQ V1 information.
public class ControlIQInfoV1Request: Message {
    public static let props = MessageProps(
        opCode: 104,
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

/// Response with Control-IQ V1 information.
public class ControlIQInfoV1Response: ControlIQInfoAbstractResponse {
    public override class var props: MessageProps {
        MessageProps(
            opCode: 105,
            size: 10,
            type: .Response,
            characteristic: .CURRENT_STATUS_CHARACTERISTICS
        )
    }

    public var closedLoopEnabled: Bool
    public var weight: Int
    public var weightUnitRaw: Int
    public var totalDailyInsulin: Int
    public var currentUserModeTypeRaw: Int
    public var byte6: Int
    public var byte7: Int
    public var byte8: Int
    public var controlStateType: Int

    public required init(cargo: Data) {
        self.closedLoopEnabled = cargo[0] != 0
        self.weight = Bytes.readShort(cargo, 1)
        self.weightUnitRaw = Int(cargo[3])
        self.totalDailyInsulin = Int(cargo[4])
        self.currentUserModeTypeRaw = Int(cargo[5])
        self.byte6 = Int(cargo[6])
        self.byte7 = Int(cargo[7])
        self.byte8 = Int(cargo[8])
        self.controlStateType = Int(cargo[9])
        super.init(cargo: cargo)
    }

    public init(closedLoopEnabled: Bool, weight: Int, weightUnit: Int, totalDailyInsulin: Int, currentUserModeType: Int, byte6: Int, byte7: Int, byte8: Int, controlStateType: Int) {
        let data = Bytes.combine(
            Bytes.firstByteLittleEndian(closedLoopEnabled ? 1 : 0),
            Bytes.firstTwoBytesLittleEndian(weight),
            Bytes.firstByteLittleEndian(weightUnit),
            Bytes.firstByteLittleEndian(totalDailyInsulin),
            Bytes.firstByteLittleEndian(currentUserModeType),
            Bytes.firstByteLittleEndian(byte6),
            Bytes.firstByteLittleEndian(byte7),
            Bytes.firstByteLittleEndian(byte8),
            Bytes.firstByteLittleEndian(controlStateType)
        )
        self.closedLoopEnabled = closedLoopEnabled
        self.weight = weight
        self.weightUnitRaw = weightUnit
        self.totalDailyInsulin = totalDailyInsulin
        self.currentUserModeTypeRaw = currentUserModeType
        self.byte6 = byte6
        self.byte7 = byte7
        self.byte8 = byte8
        self.controlStateType = controlStateType
        super.init(cargo: data)
    }

    public override func getClosedLoopEnabled() -> Bool { closedLoopEnabled }
    public override func getWeight() -> Int { weight }
    public override func getWeightUnitId() -> Int { weightUnitRaw }
    public override func getTotalDailyInsulin() -> Int { totalDailyInsulin }
    public override func getCurrentUserModeTypeId() -> Int { currentUserModeTypeRaw }
    public override func getByte6() -> Int { byte6 }
    public override func getByte7() -> Int { byte7 }
    public override func getByte8() -> Int { byte8 }
    public override func getControlStateType() -> Int { controlStateType }
}


