import Foundation

/// Request to dismiss an alert/alarm/notification on the pump.
public class DismissNotificationRequest: Message {
    public static let props = MessageProps(
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
        notificationId = Bytes.readUint32(cargo, 0)
        notificationTypeId = Bytes.readShort(cargo, 4)
    }

    public init(notificationType: NotificationType, notificationId: UInt32) {
        cargo = Bytes.combine(
            Bytes.toUint32(notificationId),
            Bytes.firstTwoBytesLittleEndian(notificationType.rawValue)
        )
        self.notificationId = notificationId
        notificationTypeId = notificationType.rawValue
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
    public static let props = MessageProps(
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
        status = Int(cargo[0])
    }

    public init(status: Int) {
        cargo = Data([UInt8(status & 0xFF)])
        self.status = status
    }
}
