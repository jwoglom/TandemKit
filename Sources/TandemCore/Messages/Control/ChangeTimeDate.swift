import Foundation

/// Request to change the pump's date/time.
public class ChangeTimeDateRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-42)),
        size: 4,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var tandemEpochTime: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        tandemEpochTime = Bytes.readUint32(cargo, 0)
    }

    public init(tandemEpochTime: UInt32) {
        cargo = Bytes.toUint32(tandemEpochTime)
        self.tandemEpochTime = tandemEpochTime
    }
}

/// Response containing status after changing date/time.
public class ChangeTimeDateResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-41)),
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
