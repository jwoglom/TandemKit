import Foundation

/// Request to set a CGM rise or fall rate alert threshold.
///
/// Cargo layout (4 bytes):
///   [0]  alertType  uint8  - 0=RISE, 1=FALL
///   [1]  enable     uint8  - 0=disabled, 1=enabled
///   [2]  mgPerDl    uint8  - rate threshold in mg/dL/min
///   [3]  bitmask    uint8  - change bitmask (bits: 0=enabled, 1=minValue)
public class CgmRiseFallAlertRequest: PumpRequest {
    public typealias Response = CgmRiseFallAlertResponse

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-60)),
        size: 4,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    public enum AlertType: Int {
        case rise = 0
        case fall = 1
    }

    public var cargo: Data
    public var alertType: Int
    public var enable: Bool
    public var mgPerDl: Int
    public var bitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        alertType = Int(cargo[0])
        enable = cargo[1] != 0
        mgPerDl = Int(cargo[2])
        bitmask = Int(cargo[3])
    }

    public init(alertType: Int, enable: Bool, mgPerDl: Int, bitmask: Int) {
        cargo = CgmRiseFallAlertRequest.buildCargo(alertType: alertType, enable: enable, mgPerDl: mgPerDl, bitmask: bitmask)
        self.alertType = alertType
        self.enable = enable
        self.mgPerDl = mgPerDl
        self.bitmask = bitmask
    }

    public static func buildCargo(alertType: Int, enable: Bool, mgPerDl: Int, bitmask: Int) -> Data {
        Bytes.combine(
            Data([UInt8(alertType & 0xFF)]),
            Data([enable ? 1 : 0]),
            Data([UInt8(mgPerDl & 0xFF)]),
            Data([UInt8(bitmask & 0xFF)])
        )
    }

    public var description: String {
        "CgmRiseFallAlertRequest(cargo=\(cargo.hexadecimalString), alertType=\(alertType), enable=\(enable), mgPerDl=\(mgPerDl), bitmask=\(bitmask))"
    }
}

/// Response after setting a CGM rise/fall alert.
public class CgmRiseFallAlertResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-59)),
        size: 1,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
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
        "CgmRiseFallAlertResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
