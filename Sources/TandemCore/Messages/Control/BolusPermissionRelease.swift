import Foundation

/// Request to release bolus permission for a previously granted bolus.
public class BolusPermissionReleaseRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-16)),
        size: 4,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .apiV2_5
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
        cargo = BolusPermissionReleaseRequest.buildCargo(bolusID: bolusID, reserve: reserve)
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
        "BolusPermissionReleaseRequest(cargo=\(cargo.hexadecimalString), bolusID=\(bolusID), reserve=\(reserve))"
    }
}

/// Response indicating whether bolus permission release succeeded.
public class BolusPermissionReleaseResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-15)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .apiV2_5
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

    /// Convenience enumeration for release status.
    public enum ReleaseStatus: Int {
        case success = 0
        case failure = 1
    }

    public var releaseStatus: ReleaseStatus? { ReleaseStatus(rawValue: status) }
    public var description: String {
        "BolusPermissionReleaseResponse(cargo=\(cargo.hexadecimalString), status=\(status), releaseStatus=\(String(describing: releaseStatus)))"
    }
}
