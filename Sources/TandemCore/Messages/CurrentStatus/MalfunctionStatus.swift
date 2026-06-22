import Foundation

/// Request any malfunction status from the pump.
public class MalfunctionStatusRequest: Message {
    public static let props = MessageProps(
        opCode: 118,
        size: 0,
        type: .Request,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
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
public class MalfunctionBitmaskStatusResponse: Message, NotificationMessage {
    public static let props = MessageProps(
        opCode: 119,
        size: 8,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
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
    
    public var notificationCount: Int { malfunctions.count }

    public var notificationIds: Set<Int> {
        Set(malfunctions.map(\.rawValue))
    }

    /// Malfunction subsystem types encoded as bit positions in the bitmask.
    public enum MalfunctionType: Int, CaseIterable, Comparable, NotificationEnum {
        case software = 1
        case cpuCore = 2
        case armMspCom = 4
        case sensor = 8
        case lipo = 16
        case touchscreen = 32
        case nvm = 64
        case display = 128
        case msp = 256
        case motor = 512
        case externalBins = 1024
        case swInit = 2048
        case vibe = 4096
        case periphPower = 8192
        case p2 = 16384
        case datalog = 32768
        case speaker = 65536
        case mspSupply = 131_072
        case calData = 262_144
        case btle = 524_288
        case ap = 1_048_576
        case rtc = 2_097_152
        case armBleCom = 4_194_304
        case overtravelStall = 8_388_608
        case undertravelStall = 16_777_216
        case pushoffStall = 33_554_432
        
        public static func < (lhs: MalfunctionType, rhs: MalfunctionType) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public static func fromBitmask(_ intMap: UInt64) -> Set<MalfunctionType> {
            var current = Set<MalfunctionType>()
            for type in MalfunctionType.allCases {
                if (intMap >> type.rawValue) & 1 == 1 {
                    current.insert(type)
                }
            }
            return current
        }
        
        public var id: Int { rawValue }
        
        public var notificationDescription: String? {
            switch self {
            case .software:
                return String(localized: "Software", comment: "MalfunctionType: software")
            case .cpuCore:
                return String(localized: "CPU Core", comment: "MalfunctionType: cpuCore")
            case .armMspCom:
                return String(localized: "ARM MSP", comment: "MalfunctionType: armMspCom")
            case .sensor:
                return String(localized: "Sensor", comment: "MalfunctionType: sensor")
            case .lipo:
                return String(localized: "Lipo", comment: "MalfunctionType: lipo")
            case .touchscreen:
                return String(localized: "Touchscreen", comment: "MalfunctionType: touchscreen")
            case .nvm:
                return String(localized: "NVM", comment: "MalfunctionType: nvm")
            case .display:
                return String(localized: "Display", comment: "MalfunctionType: display")
            case .msp:
                return String(localized: "MSP", comment: "MalfunctionType: msp")
            case .motor:
                return String(localized: "Motor", comment: "MalfunctionType: motor")
            case .externalBins:
                return String(localized: "External Binaries", comment: "MalfunctionType: externalBins")
            case .swInit:
                return String(localized: "Software init", comment: "MalfunctionType: swInit")
            case .vibe:
                return String(localized: "Vibe", comment: "MalfunctionType: vibe")
            case .periphPower:
                return String(localized: "Peripheral Power", comment: "MalfunctionType: periphPower")
            case .p2:
                return String(localized: "P2", comment: "MalfunctionType: p2")
            case .datalog:
                return String(localized: "Datalog", comment: "MalfunctionType: datalog")
            case .speaker:
                return String(localized: "Speaker", comment: "MalfunctionType: speaker")
            case .mspSupply:
                return String(localized: "MSP Supply", comment: "MalfunctionType: mspSupply")
            case .calData:
                return String(localized: "CalData", comment: "MalfunctionType: calData")
            case .btle:
                return String(localized: "BTLE", comment: "MalfunctionType: btle")
            case .ap:
                return String(localized: "AP", comment: "MalfunctionType: ap")
            case .rtc:
                return String(localized: "RTC", comment: "MalfunctionType: rtc")
            case .armBleCom:
                return String(localized: "ARM BLE", comment: "MalfunctionType: armBleCom")
            case .overtravelStall:
                return String(localized: "Overtravel Stall", comment: "MalfunctionType: overtravelStall")
            case .undertravelStall:
                return String(localized: "Undertravel Stall", comment: "MalfunctionType: undertravelStall")
            case .pushoffStall:
                return String(localized: "Pushoff Stall", comment: "MalfunctionType: pushoffStall")
            }
        }
    }

    public var description: String {
        "MalfunctionBitmaskStatusResponse(cargo=\(cargo.hexadecimalString), bitmask=\(bitmask), malfunctions=\(malfunctions))"
    }
}
