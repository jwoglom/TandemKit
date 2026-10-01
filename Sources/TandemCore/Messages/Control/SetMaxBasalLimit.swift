import Foundation

/// Request to set the maximum hourly basal rate.
public class SetMaxBasalLimitRequest: PumpRequest {
    public typealias Response = SetMaxBasalLimitResponse

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-120)),
        size: 4,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var maxHourlyBasalMilliunits: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        maxHourlyBasalMilliunits = Int(Bytes.readUint32(cargo, 0))
    }

    public static let minBasalLimitMilliunits = 1000
    public static let maxBasalLimitMilliunits = 15000

    public init(maxHourlyBasalMilliunits: Int) throws {
        guard (Self.minBasalLimitMilliunits ... Self.maxBasalLimitMilliunits).contains(maxHourlyBasalMilliunits) else {
            throw PumpCommError.requestConstructionFailed(
                reason: "max basal limit \(maxHourlyBasalMilliunits) mU/h is outside 1 U/h to 15 U/h"
            )
        }
        cargo = Bytes.toUint32(UInt32(maxHourlyBasalMilliunits))
        self.maxHourlyBasalMilliunits = maxHourlyBasalMilliunits
    }

    public var description: String {
        "SetMaxBasalLimitRequest(cargo=\(cargo.hexadecimalString), maxHourlyBasalMilliunits=\(maxHourlyBasalMilliunits))"
    }
}

/// Response after setting the max basal limit.
public class SetMaxBasalLimitResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-119)),
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
        "SetMaxBasalLimitResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
