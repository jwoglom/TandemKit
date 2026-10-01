import Foundation

/// Request to set the maximum bolus amount.
public class SetMaxBolusLimitRequest: PumpRequest {
    public typealias Response = SetMaxBolusLimitResponse

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-122)),
        size: 2,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var maxBolusMilliunits: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        maxBolusMilliunits = Bytes.readShort(cargo, 0)
    }

    public static let minBolusLimitMilliunits = 1000
    public static let maxBolusLimitMilliunits = 25000

    public init(maxBolusMilliunits: Int) throws {
        guard (Self.minBolusLimitMilliunits ... Self.maxBolusLimitMilliunits).contains(maxBolusMilliunits) else {
            throw PumpCommError.requestConstructionFailed(
                reason: "max bolus limit \(maxBolusMilliunits) mU is outside 1 U to 25 U"
            )
        }
        cargo = Bytes.firstTwoBytesLittleEndian(maxBolusMilliunits)
        self.maxBolusMilliunits = maxBolusMilliunits
    }

    public var description: String {
        "SetMaxBolusLimitRequest(cargo=\(cargo.hexadecimalString), maxBolusMilliunits=\(maxBolusMilliunits))"
    }
}

/// Response after setting the max bolus limit.
public class SetMaxBolusLimitResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-121)),
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
        "SetMaxBolusLimitResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
