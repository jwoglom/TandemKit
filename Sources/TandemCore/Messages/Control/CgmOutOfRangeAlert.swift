import Foundation

/// Request to set the CGM out-of-range alert configuration.
///
/// Cargo layout (3 bytes):
///   [0]  enable      uint8  - 0=disabled, 1=enabled
///   [1]  alertDelay  uint8  - delay before alert (minutes)
///   [2]  bitmask     uint8  - change bitmask (bits: 0=enabled, 1=delayBeforeAlert)
public class CgmOutOfRangeAlertRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-58)),
        size: 3,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var enable: Bool
    public var alertDelay: Int
    public var bitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        enable = cargo[0] != 0
        alertDelay = Int(cargo[1])
        bitmask = Int(cargo[2])
    }

    public init(enable: Bool, alertDelay: Int, bitmask: Int) {
        cargo = CgmOutOfRangeAlertRequest.buildCargo(enable: enable, alertDelay: alertDelay, bitmask: bitmask)
        self.enable = enable
        self.alertDelay = alertDelay
        self.bitmask = bitmask
    }

    public static func buildCargo(enable: Bool, alertDelay: Int, bitmask: Int) -> Data {
        Bytes.combine(
            Data([enable ? 1 : 0]),
            Data([UInt8(alertDelay & 0xFF)]),
            Data([UInt8(bitmask & 0xFF)])
        )
    }

    public var description: String {
        "CgmOutOfRangeAlertRequest(cargo=\(cargo.hexadecimalString), enable=\(enable), alertDelay=\(alertDelay), bitmask=\(bitmask))"
    }
}

/// Response after setting the CGM out-of-range alert.
public class CgmOutOfRangeAlertResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-57)),
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
        "CgmOutOfRangeAlertResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
