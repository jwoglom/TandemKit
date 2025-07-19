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
    public static var props = MessageProps(
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
    public static var props = MessageProps(
        opCode: 105,
        size: 10,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var closedLoopEnabled: Bool
    public var weight: Int
    public var weightUnit: Int
    public var totalDailyInsulin: Int
    public var currentUserModeType: Int
    public var byte6: Int
    public var byte7: Int
    public var byte8: Int
    public var controlStateType: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.closedLoopEnabled = cargo[0] != 0
        self.weight = Bytes.readShort(cargo, 1)
        self.weightUnit = Int(cargo[3])
        self.totalDailyInsulin = Int(cargo[4])
        self.currentUserModeType = Int(cargo[5])
        self.byte6 = Int(cargo[6])
        self.byte7 = Int(cargo[7])
        self.byte8 = Int(cargo[8])
        self.controlStateType = Int(cargo[9])
    }

    public init(closedLoopEnabled: Bool, weight: Int, weightUnit: Int, totalDailyInsulin: Int, currentUserModeType: Int, byte6: Int, byte7: Int, byte8: Int, controlStateType: Int) {
        self.cargo = Bytes.combine(
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
        self.weightUnit = weightUnit
        self.totalDailyInsulin = totalDailyInsulin
        self.currentUserModeType = currentUserModeType
        self.byte6 = byte6
        self.byte7 = byte7
        self.byte8 = byte8
        self.controlStateType = controlStateType
    }

    public override var props: MessageProps { ControlIQInfoV1Response.props }

    public override func getClosedLoopEnabled() -> Bool { closedLoopEnabled }
    public override func getWeight() -> Int { weight }
    public override func getWeightUnitId() -> Int { weightUnit }
    public override func getTotalDailyInsulin() -> Int { totalDailyInsulin }
    public override func getCurrentUserModeTypeId() -> Int { currentUserModeType }
    public override func getByte6() -> Int { byte6 }
    public override func getByte7() -> Int { byte7 }
    public override func getByte8() -> Int { byte8 }
    public override func getControlStateType() -> Int { controlStateType }
}

/// Abstract superclass with common enum helpers used by ControlIQInfo responses.
public class ControlIQInfoAbstractResponse: Message {
    public func getClosedLoopEnabled() -> Bool { fatalError("abstract") }
    public func getWeight() -> Int { fatalError("abstract") }
    public func getWeightUnitId() -> Int { fatalError("abstract") }
    public func getTotalDailyInsulin() -> Int { fatalError("abstract") }
    public func getCurrentUserModeTypeId() -> Int { fatalError("abstract") }
    public func getByte6() -> Int { fatalError("abstract") }
    public func getByte7() -> Int { fatalError("abstract") }
    public func getByte8() -> Int { fatalError("abstract") }
    public func getControlStateType() -> Int { fatalError("abstract") }

    public enum UserModeType: Int {
        case STANDARD = 0
        case SLEEP = 1
        case EXERCISE = 2
        case NOT_SUPPORTED_IN_CURRENT_FIRMWARE__EATING_SOON = 3
    }

    public enum WeightUnit: Int {
        case KILOGRAMS = 0
        case POUNDS = 1
    }

    public func getCurrentUserModeType() -> UserModeType? {
        return UserModeType(rawValue: getCurrentUserModeTypeId())
    }

    public func getWeightUnit() -> WeightUnit? {
        return WeightUnit(rawValue: getWeightUnitId())
    }
}

