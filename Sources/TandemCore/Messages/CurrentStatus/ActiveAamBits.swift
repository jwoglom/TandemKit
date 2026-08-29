import Foundation

public class ActiveAamBitsRequest: PumpRequest {
    public typealias Response = ActiveAamBitsResponse

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-110)),
        size: 1,
        type: .Request,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
        minApi: .mobiApiV3_5
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init(aamType: UInt8) {
        cargo = Data([aamType])
    }

    public var description: String {
        "ActiveAamBitsRequest(cargo=\(cargo.hexadecimalString))"
    }
}

public class ActiveAamBitsResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-109)),
        size: 17,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
        minApi: .mobiApiV3_5
    )

    public var cargo: Data
    public var unacknowledgedBitmask: UInt64
    public var activeBitmask: UInt64
    public var aamType: AamType

    public required init(cargo: Data) {
        self.cargo = cargo
        unacknowledgedBitmask = Bytes.readUint64(cargo, 0)
        activeBitmask = Bytes.readUint64(cargo, 8)
        aamType = AamType(rawValue: Int(cargo[16])) ?? .unknown
    }

    public init(unacknowledgedBitmask: UInt64, activeBitmask: UInt64, aamType: AamType) {
        cargo = Bytes.combine(
            Bytes.toUint64(unacknowledgedBitmask),
            Bytes.toUint64(activeBitmask),
            Data([UInt8(truncatingIfNeeded: aamType.rawValue)])
        )
        self.unacknowledgedBitmask = unacknowledgedBitmask
        self.activeBitmask = activeBitmask
        self.aamType = aamType
    }

    public func hasActiveBit(_ bit: Int) -> Bool {
        guard (0 ..< 64).contains(bit) else {
            return false
        }
        return ((activeBitmask >> UInt64(bit)) & 1) == 1
    }

    public func hasUnacknowledgedBit(_ bit: Int) -> Bool {
        guard (0 ..< 64).contains(bit) else {
            return false
        }
        return ((unacknowledgedBitmask >> UInt64(bit)) & 1) == 1
    }

    public enum AamType: Int, CaseIterable {
        case reminder = 0
        case alert = 1
        case alarm = 2
        case cgmAlert = 3
        case malfunction = 4
        case none = 5
        case unknown = -1
    }

    public var description: String {
        "ActiveAamBitsResponse(cargo=\(cargo.hexadecimalString), unacknowledgedBitmask=\(unacknowledgedBitmask), activeBitmask=\(activeBitmask), aamType=\(aamType))"
    }
}
