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
    public var executeExtraAction: Bool

    public required init(cargo: Data) {
        self.cargo = cargo
        notificationId = Bytes.readUint32(cargo, 0)
        notificationTypeId = Int(cargo[4] & 0xFF)
        executeExtraAction = (cargo[5] & 0xFF) != 0
    }

    public init(notificationType: NotificationType, notificationId: UInt32, executeExtraAction: Bool = false) {
        cargo = Bytes.combine(
            Bytes.toUint32(notificationId),
            Bytes.firstByteLittleEndian(notificationType.rawValue),
            Bytes.firstByteLittleEndian(executeExtraAction ? 1 : 0)
        )
        self.notificationId = notificationId
        notificationTypeId = notificationType.rawValue
        self.executeExtraAction = executeExtraAction
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

    public var description: String {
        "DismissNotificationRequest(cargo=\(cargo.hexadecimalString), notificationId=\(notificationId), notificationType=\(String(describing: notificationType)), notificationTypeId=\(notificationTypeId), executeExtraAction=\(executeExtraAction))"
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

    public var description: String {
        "DismissNotificationResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
