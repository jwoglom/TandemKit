import Foundation

/// Request any malfunction status from the pump.
public class MalfunctionStatusRequest: Message {
    public static let props = MessageProps(
        opCode: 118,
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
        "MalfunctionStatusRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response with a bitmask of active malfunction types.
public class MalfunctionBitmaskStatusResponse: Message {
    public static let props = MessageProps(
        opCode: 119,
        size: 8,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var bitmask: UInt64
    public var malfunctions: Set<MalfunctionType>

    public required init(cargo: Data) {
        self.cargo = cargo
        bitmask = Bytes.readUint64(cargo, 0)
        malfunctions = MalfunctionType.fromBitmask(bitmask)
    }

    public init(bitmask: UInt64) {
        cargo = Bytes.toUint64(bitmask)
        self.bitmask = bitmask
        malfunctions = MalfunctionType.fromBitmask(bitmask)
    }

    public func hasMalfunctionBit(_ type: MalfunctionType) -> Bool {
        (bitmask & type.rawValue) != 0
    }

    /// Check by raw bit position (used by HighestAamResponse.matchesActiveMalfunction).
    public func hasMalfunctionBit(_ bit: Int) -> Bool {
        (bitmask & (1 << bit)) != 0
    }

    /// Malfunction subsystem types encoded as bit positions in the bitmask.
    public enum MalfunctionType: UInt64, CaseIterable {
        case software       = 1
        case cpuCore        = 2
        case armMspCom      = 4
        case sensor         = 8
        case lipo           = 16
        case touchscreen    = 32
        case nvm            = 64
        case display        = 128
        case msp            = 256
        case motor          = 512
        case externalBins   = 1024
        case swInit         = 2048
        case vibe           = 4096
        case periphPower    = 8192
        case p2             = 16384
        case datalog        = 32768
        case speaker        = 65536
        case mspSupply      = 131072
        case calData        = 262144
        case btle           = 524288
        case ap             = 1048576
        case rtc            = 2097152
        case armBleCom      = 4194304
        case overtravelStall = 8388608
        case undertravelStall = 16777216
        case pushoffStall   = 33554432

        public static func fromBitmask(_ bitmask: UInt64) -> Set<MalfunctionType> {
            var result = Set<MalfunctionType>()
            for type in MalfunctionType.allCases {
                if (bitmask & type.rawValue) != 0 {
                    result.insert(type)
                }
            }
            return result
        }
    }

    public var description: String {
        "MalfunctionBitmaskStatusResponse(cargo=\(cargo.hexadecimalString), bitmask=\(bitmask), malfunctions=\(malfunctions))"
    }
}
