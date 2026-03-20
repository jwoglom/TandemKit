import Foundation

/// Request an additional bolus for a previously-permitted bolusID.
public class AdditionalBolusRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-6)),
        size: 4,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true
    )

    public var cargo: Data
    public var bolusID: Int
    public var reserve: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        bolusID = Bytes.readShort(cargo, 0)
        reserve = Bytes.readShort(cargo, 2)
    }

    public init(bolusID: Int, reserve: Int = 0) {
        cargo = AdditionalBolusRequest.buildCargo(bolusID: bolusID, reserve: reserve)
        self.bolusID = bolusID
        self.reserve = reserve
    }

    public static func buildCargo(bolusID: Int, reserve: Int) -> Data {
        Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(bolusID),
            Bytes.firstTwoBytesLittleEndian(reserve)
        )
    }

    public var description: String {
        "AdditionalBolusRequest(cargo=\(cargo.hexadecimalString), bolusID=\(bolusID), reserve=\(reserve))"
    }
}

/// Response to an additional bolus request.
public class AdditionalBolusResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-5)),
        size: 5,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true
    )

    public var cargo: Data
    public var status: Int
    public var bolusId: Int
    public var reserve: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        status = Int(cargo[0])
        bolusId = Bytes.readShort(cargo, 1)
        reserve = Bytes.readShort(cargo, 3)
    }

    public init(status: Int, bolusId: Int, reserve: Int) {
        cargo = AdditionalBolusResponse.buildCargo(status: status, bolusId: bolusId, reserve: reserve)
        self.status = status
        self.bolusId = bolusId
        self.reserve = reserve
    }

    public static func buildCargo(status: Int, bolusId: Int, reserve: Int) -> Data {
        Bytes.combine(
            Data([UInt8(status & 0xFF)]),
            Bytes.firstTwoBytesLittleEndian(bolusId),
            Bytes.firstTwoBytesLittleEndian(reserve)
        )
    }

    public var wasAccepted: Bool { status == 0 }

    public var description: String {
        "AdditionalBolusResponse(cargo=\(cargo.hexadecimalString), status=\(status), bolusId=\(bolusId), reserve=\(reserve))"
    }
}
