//
//  InsulinStatus.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of InsulinStatusRequest and InsulinStatusResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/InsulinStatusRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/InsulinStatusResponse.java
//

import Foundation

/// Request the current amount of insulin remaining in the pump.
public class InsulinStatusRequest: Message {
    public static var props = MessageProps(
        opCode: 36,
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

/// Response describing remaining insulin in the reservoir.
public class InsulinStatusResponse: Message {
    public static var props = MessageProps(
        opCode: 37,
        size: 4,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var currentInsulinAmount: Int
    public var isEstimate: Int
    public var insulinLowAmount: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.currentInsulinAmount = Bytes.readShort(cargo, 0)
        self.isEstimate = Int(cargo[2])
        self.insulinLowAmount = Int(cargo[3])
    }

    public init(currentInsulinAmount: Int, isEstimate: Int, insulinLowAmount: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(currentInsulinAmount),
            Bytes.firstByteLittleEndian(isEstimate),
            Bytes.firstByteLittleEndian(insulinLowAmount)
        )
        self.currentInsulinAmount = currentInsulinAmount
        self.isEstimate = isEstimate
        self.insulinLowAmount = insulinLowAmount
    }
}

