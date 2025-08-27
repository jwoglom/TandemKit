//
//  OtherNotificationStatus.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of OtherNotificationStatusRequest and OtherNotificationStatusResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/OtherNotificationStatusRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/OtherNotificationStatusResponse.java
//

import Foundation

/// Request miscellaneous notification status (Mobi only).
public class OtherNotificationStatusRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-110)),
        size: 1,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .mobiApiV3_5
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data([0])
    }
}

/// Response for miscellaneous notifications (Mobi only).
public class OtherNotificationStatusResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-109)),
        size: 17,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .mobiApiV3_5
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Bytes.emptyBytes(Int(Self.props.size))
    }
}

