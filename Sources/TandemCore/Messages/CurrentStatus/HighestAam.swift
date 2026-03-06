import Foundation

public class HighestAamRequest: Message {
    public static let props = MessageProps(
        opCode: 120,
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "HighestAamRequest(cargo=\(cargo.hexadecimalString))"
    }
}

public class HighestAamResponse: Message {
    public static let props = MessageProps(
        opCode: 121,
        size: 11,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        variableSize: true
    )

    public var cargo: Data
    public var aamId: UInt32
    public var faultId: UInt32
    public var remaining: Data

    public required init(cargo: Data) {
        precondition(cargo.count == 10 || cargo.count == 11, "Unexpected HighestAamResponse payload length: \(cargo.count)")
        self.cargo = cargo
        aamId = Bytes.readUint32(cargo, 0)
        faultId = Bytes.readUint32(cargo, 4)
        remaining = Bytes.dropFirstN(cargo, 8)
    }

    public init(aamId: UInt32, faultId: UInt32, remaining: Data = Data()) {
        cargo = Bytes.combine(
            Bytes.toUint32(aamId),
            Bytes.toUint32(faultId),
            remaining
        )
        self.aamId = aamId
        self.faultId = faultId
        self.remaining = remaining
    }

    public var description: String {
        "HighestAamResponse(cargo=\(cargo.hexadecimalString), aamId=\(aamId), faultId=\(faultId), remaining=\(remaining.hexadecimalString))"
    }
}
