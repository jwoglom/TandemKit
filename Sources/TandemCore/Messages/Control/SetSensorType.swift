import Foundation

/// Request to set the CGM sensor type.
public class SetSensorTypeRequest: PumpRequest {
    public typealias Response = SetSensorTypeResponse

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-64)),
        size: 1,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var sensorTypeId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        sensorTypeId = cargo.isEmpty ? 0 : Int(cargo[0])
    }

    public init(sensorTypeId: Int) {
        cargo = Data([UInt8(sensorTypeId & 0xFF)])
        self.sensorTypeId = sensorTypeId
    }

    /// Convenience initializer using CGMStatusV2Response.CGMSensorType values:
    /// dexcomG6 = 1, dexcomG7 = 3
    public convenience init(sensorType: CGMStatusV2Response.CGMSensorType) {
        self.init(sensorTypeId: sensorType.rawValue)
    }

    public var description: String {
        "SetSensorTypeRequest(cargo=\(cargo.hexadecimalString), sensorTypeId=\(sensorTypeId))"
    }
}

/// Response after setting the CGM sensor type.
///
/// Cargo layout (2 bytes):
///   [0] status                uint8 - 0=ACK, 1=NACK
///   [1] statusAcknowledgement uint8 - StatusAcknowledgement ordinal
public class SetSensorTypeResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-63)),
        size: 2,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var status: Int
    public var statusAcknowledgement: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        status = Int(cargo[0])
        statusAcknowledgement = Int(cargo[1])
    }

    public init(status: Int, statusAcknowledgement: Int) {
        cargo = Data([UInt8(status & 0xFF), UInt8(statusAcknowledgement & 0xFF)])
        self.status = status
        self.statusAcknowledgement = statusAcknowledgement
    }

    public enum StatusAcknowledgementType: Int {
        case success = 0
        case cgmSessionAlreadyActive = 1
        case invalidCgmType = 2
        case malfunctionActive = 3
        case missingOrInvalidCgmSupportPackage = 4
        case invalidScreenState = 5
        case unknown = 6
    }

    public var statusAcknowledgementType: StatusAcknowledgementType? {
        StatusAcknowledgementType(rawValue: statusAcknowledgement)
    }

    public var description: String {
        "SetSensorTypeResponse(cargo=\(cargo.hexadecimalString), status=\(status), statusAcknowledgement=\(statusAcknowledgement))"
    }
}
