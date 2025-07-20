//
//  DismissNotification.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of DismissNotificationRequest and DismissNotificationResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/DismissNotificationRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/DismissNotificationResponse.java
//

import Foundation

/// Request to dismiss an alert/alarm/notification on the pump.
public class DismissNotificationRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-72)),
        size: 6,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var notificationId: UInt32
    public var notificationTypeId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.notificationId = Bytes.readUint32(cargo, 0)
        self.notificationTypeId = Bytes.readShort(cargo, 4)
    }

    public init(notificationType: NotificationType, notificationId: UInt32) {
        self.cargo = Bytes.combine(
            Bytes.toUint32(notificationId),
            Bytes.firstTwoBytesLittleEndian(notificationType.rawValue)
        )
        self.notificationId = notificationId
        self.notificationTypeId = notificationType.rawValue
    }

    public var notificationType: NotificationType? {
        NotificationType(rawValue: notificationTypeId)
    }

    public enum NotificationType: Int {
        case reminder = 0
        case alert = 1
        case alarm = 2
        case cgmAlert = 3
    }
}

/// Response after requesting a notification dismissal.
public class DismissNotificationResponse: Message, StatusMessage {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-71)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var status: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.status = Int(cargo[0])
    }

    public init(status: Int) {
        self.cargo = Data([UInt8(status & 0xFF)])
        self.status = status
    }
}

