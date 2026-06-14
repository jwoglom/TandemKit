import Foundation

/// Request to prime tubing with suspend.
public class PrimeTubingSuspendRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-18)),
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
        "PrimeTubingSuspendRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response after requesting a prime tubing suspend.
///
/// Cargo layout (3 bytes):
///   [0] statusCode  uint8  - 0=ACK/success
///   [1] unused padding
///   [2] reserve     uint8
public class PrimeTubingSuspendResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-17)),
        size: 3,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var status: Int
    public var reserve: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        status = Int(cargo[0])
        // cargo[1] is unused padding
        reserve = Int(cargo[2])
    }

    public init(status: Int, reserve: Int) {
        cargo = PrimeTubingSuspendResponse.buildCargo(status: status, reserve: reserve)
        self.status = status
        self.reserve = reserve
    }

    public static func buildCargo(status: Int, reserve: Int) -> Data {
        Bytes.combine(
            Data([UInt8(status & 0xFF)]),
            Data([0]),
            Data([UInt8(reserve & 0xFF)])
        )
    }

    public var description: String {
        "PrimeTubingSuspendResponse(cargo=\(cargo.hexadecimalString), status=\(status), reserve=\(reserve))"
    }
}
