import Foundation

/// Request to stop an active Dexcom CGM sensor session.
public class StopDexcomCGMSensorSessionRequest: PumpRequest {
    public typealias Response = StopDexcomCGMSensorSessionResponse

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-76)),
        size: 0,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "StopDexcomCGMSensorSessionRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response to stopping the Dexcom CGM session.
public class StopDexcomCGMSensorSessionResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-75)),
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
        "StopDexcomCGMSensorSessionResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
