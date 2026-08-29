import Foundation

/// Request to fill the cannula with insulin. Pump must be suspended.
public class FillCannulaRequest: PumpRequest {
    public typealias Response = FillCannulaResponse

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-104)),
        size: 2,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var primeSizeMilliUnits: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        primeSizeMilliUnits = Bytes.readShort(cargo, 0)
    }

    public init(primeSizeMilliUnits: Int) {
        cargo = Bytes.firstTwoBytesLittleEndian(primeSizeMilliUnits)
        self.primeSizeMilliUnits = primeSizeMilliUnits
    }

    public var description: String {
        "FillCannulaRequest(cargo=\(cargo.hexadecimalString), primeSizeMilliUnits=\(primeSizeMilliUnits))"
    }
}

/// Response to FillCannulaRequest.
public class FillCannulaResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-103)),
        size: 1,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
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
        "FillCannulaResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
