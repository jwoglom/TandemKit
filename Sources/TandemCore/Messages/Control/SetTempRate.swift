import Foundation

/// Request to set a temporary basal rate.
public class SetTempRateRequest: PumpRequest {
    public typealias Response = SetTempRateResponse

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-92)),
        size: 6,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var minutes: Int
    public var percent: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        let ms = Bytes.readUint32(cargo, 0)
        minutes = Int(ms) / 1000 / 60
        percent = Bytes.readShort(cargo, 4)
    }

    public init(minutes: Int, percent: Int) {
        cargo = Bytes.combine(
            Bytes.toUint32(UInt32(minutes * 60 * 1000)),
            Bytes.firstTwoBytesLittleEndian(percent)
        )
        self.minutes = minutes
        self.percent = percent
    }

    public var description: String {
        "SetTempRateRequest(cargo=\(cargo.hexadecimalString), minutes=\(minutes), percent=\(percent))"
    }
}

/// Response confirming a temp rate was set.
public class SetTempRateResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-91)),
        size: 4,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var status: Int
    public var tempRateId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        status = Int(cargo[0])
        tempRateId = Bytes.readShort(cargo, 1)
    }

    public init(status: Int, tempRateId: Int) {
        cargo = Bytes.combine(
            Data([UInt8(status & 0xFF)]),
            Bytes.firstTwoBytesLittleEndian(tempRateId)
        )
        self.status = status
        self.tempRateId = tempRateId
    }

    public var description: String {
        "SetTempRateResponse(cargo=\(cargo.hexadecimalString), status=\(status), tempRateId=\(tempRateId))"
    }
}
