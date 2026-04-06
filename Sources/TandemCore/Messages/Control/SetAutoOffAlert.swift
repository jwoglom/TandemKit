import Foundation

/// Request to set the Auto-Off alert configuration.
///
/// Cargo layout (4 bytes, little-endian):
///   [0]   enableAutoOff    uint8   - 0=disabled, 1=enabled
///   [1-2] autoOffDuration  uint16  - duration in minutes before auto-off
///   [3]   bitmask          uint8   - change bitmask (bits: 0=enableAutoOff, 1=autoOffDuration)
public class SetAutoOffAlertRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-32)),
        size: 4,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var enableAutoOff: Bool
    public var autoOffDuration: Int
    public var bitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        enableAutoOff = cargo[0] != 0
        autoOffDuration = Bytes.readShort(cargo, 1)
        bitmask = Int(cargo[3])
    }

    public init(enableAutoOff: Bool, autoOffDuration: Int, bitmask: Int) {
        cargo = SetAutoOffAlertRequest.buildCargo(
            enableAutoOff: enableAutoOff,
            autoOffDuration: autoOffDuration,
            bitmask: bitmask
        )
        self.enableAutoOff = enableAutoOff
        self.autoOffDuration = autoOffDuration
        self.bitmask = bitmask
    }

    public static func buildCargo(enableAutoOff: Bool, autoOffDuration: Int, bitmask: Int) -> Data {
        Bytes.combine(
            Data([enableAutoOff ? 1 : 0]),
            Bytes.firstTwoBytesLittleEndian(autoOffDuration),
            Data([UInt8(bitmask & 0xFF)])
        )
    }

    public var description: String {
        "SetAutoOffAlertRequest(cargo=\(cargo.hexadecimalString), enableAutoOff=\(enableAutoOff), autoOffDuration=\(autoOffDuration), bitmask=\(bitmask))"
    }
}

/// Response after setting the Auto-Off alert.
public class SetAutoOffAlertResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-31)),
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
        "SetAutoOffAlertResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
