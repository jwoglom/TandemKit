import Foundation

/// Request to set a CGM high or low alert threshold.
///
/// Cargo layout (7 bytes, little-endian):
///   [0-1] threshold         uint16  - alert threshold in mg/dL
///   [2-3] repeatDuration    uint16  - repeat duration in minutes
///   [4]   alertType         uint8   - 0=HIGH, 1=LOW
///   [5]   enableAlert       uint8   - 0=disabled, 1=enabled
///   [6]   bitmask           uint8   - change bitmask (bits: 0=enabled, 1=threshold, 2=repeatDuration)
public class CgmHighLowAlertRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-62)),
        size: 7,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public enum AlertType: Int {
        case high = 0
        case low = 1
    }

    public var cargo: Data
    public var threshold: Int
    public var repeatDurationMinutes: Int
    public var alertType: Int
    public var enableAlert: Bool
    public var bitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        threshold = Bytes.readShort(cargo, 0)
        repeatDurationMinutes = Bytes.readShort(cargo, 2)
        alertType = Int(cargo[4])
        enableAlert = cargo[5] != 0
        bitmask = Int(cargo[6])
    }

    public init(alertType: Int, threshold: Int, repeatDurationMinutes: Int, enableAlert: Bool, bitmask: Int) {
        cargo = CgmHighLowAlertRequest.buildCargo(
            alertType: alertType,
            threshold: threshold,
            repeatDurationMinutes: repeatDurationMinutes,
            enableAlert: enableAlert,
            bitmask: bitmask
        )
        self.alertType = alertType
        self.threshold = threshold
        self.repeatDurationMinutes = repeatDurationMinutes
        self.enableAlert = enableAlert
        self.bitmask = bitmask
    }

    public static func buildCargo(
        alertType: Int,
        threshold: Int,
        repeatDurationMinutes: Int,
        enableAlert: Bool,
        bitmask: Int
    ) -> Data {
        Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(threshold),
            Bytes.firstTwoBytesLittleEndian(repeatDurationMinutes),
            Data([UInt8(alertType & 0xFF)]),
            Data([enableAlert ? 1 : 0]),
            Data([UInt8(bitmask & 0xFF)])
        )
    }

    public var description: String {
        "CgmHighLowAlertRequest(cargo=\(cargo.hexadecimalString), threshold=\(threshold), repeatDurationMinutes=\(repeatDurationMinutes), alertType=\(alertType), enableAlert=\(enableAlert), bitmask=\(bitmask))"
    }
}

/// Response after setting a CGM high/low alert.
public class CgmHighLowAlertResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-61)),
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
        "CgmHighLowAlertResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
