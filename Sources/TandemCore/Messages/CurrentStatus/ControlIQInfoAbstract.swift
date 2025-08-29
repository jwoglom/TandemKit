//
//  ControlIQInfoAbstract.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift translation of ControlIQInfoAbstractResponse
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/ControlIQInfoAbstractResponse.java
//

import Foundation

/// Base response shared by ControlIQInfoV1 and ControlIQInfoV2.
public class ControlIQInfoAbstractResponse: Message {
    public class var props: MessageProps {
        MessageProps(
            opCode: 0,
            size: 0,
            type: .Response,
            characteristic: .CURRENT_STATUS_CHARACTERISTICS
        )
    }

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public func getClosedLoopEnabled() -> Bool { fatalError("abstract") }
    public func getWeight() -> Int { fatalError("abstract") }
    public func getWeightUnitId() -> Int { fatalError("abstract") }
    public func getTotalDailyInsulin() -> Int { fatalError("abstract") }
    public func getCurrentUserModeTypeId() -> Int { fatalError("abstract") }
    public func getByte6() -> Int { fatalError("abstract") }
    public func getByte7() -> Int { fatalError("abstract") }
    public func getByte8() -> Int { fatalError("abstract") }
    public func getControlStateType() -> Int { fatalError("abstract") }

    public var currentUserModeType: UserModeType? { UserModeType(rawValue: getCurrentUserModeTypeId()) }
    public var weightUnit: WeightUnit? { WeightUnit(rawValue: getWeightUnitId()) }

    /// ControlIQ user modes.
    public enum UserModeType: Int {
        case standard = 0
        case sleep = 1
        case exercise = 2
        case notSupportedEatingSoon = 3
    }

    /// Weight units.
    public enum WeightUnit: Int {
        case kilograms = 0
        case pounds = 1
    }
}

