import Foundation

/// Request to set the low insulin alert threshold.
///
/// Cargo layout (1 byte):
///   [0]  insulinThreshold  uint8  - low insulin threshold in units
public class SetLowInsulinAlertRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-34)),
        size: 1,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var insulinThreshold: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        insulinThreshold = Int(cargo[0])
    }

    public init(insulinThreshold: Int) {
        cargo = Data([UInt8(insulinThreshold & 0xFF)])
        self.insulinThreshold = insulinThreshold
    }

    public var description: String {
        "SetLowInsulinAlertRequest(cargo=\(cargo.hexadecimalString), insulinThreshold=\(insulinThreshold))"
    }
}

/// Response after setting the low insulin alert.
public class SetLowInsulinAlertResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-33)),
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
        "SetLowInsulinAlertResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
