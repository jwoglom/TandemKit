import Foundation

/// Request Control-IQ insulin on board information.
public class ControlIQIOBRequest: Message {
    public static let props = MessageProps(
        opCode: 108,
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
}

/// Response with Control-IQ insulin on board information.
public class ControlIQIOBResponse: Message {
    public static let props = MessageProps(
        opCode: 109,
        size: 17,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var mudaliarIOB: UInt32
    public var timeRemainingSeconds: UInt32
    public var mudaliarTotalIOB: UInt32
    public var swan6hrIOB: UInt32
    public var iobType: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        mudaliarIOB = Bytes.readUint32(cargo, 0)
        timeRemainingSeconds = Bytes.readUint32(cargo, 4)
        mudaliarTotalIOB = Bytes.readUint32(cargo, 8)
        swan6hrIOB = Bytes.readUint32(cargo, 12)
        iobType = Int(cargo[16])
    }

    public init(mudaliarIOB: UInt32, timeRemainingSeconds: UInt32, mudaliarTotalIOB: UInt32, swan6hrIOB: UInt32, iobType: Int) {
        cargo = Bytes.combine(
            Bytes.toUint32(mudaliarIOB),
            Bytes.toUint32(timeRemainingSeconds),
            Bytes.toUint32(mudaliarTotalIOB),
            Bytes.toUint32(swan6hrIOB),
            Bytes.firstByteLittleEndian(iobType)
        )
        self.mudaliarIOB = mudaliarIOB
        self.timeRemainingSeconds = timeRemainingSeconds
        self.mudaliarTotalIOB = mudaliarTotalIOB
        self.swan6hrIOB = swan6hrIOB
        self.iobType = iobType
    }

    /// The method of IOB calculation used.
    public var type: IOBType? {
        IOBType(rawValue: iobType)
    }

    public enum IOBType: Int {
        case MUDALIAR = 0
        case SWAN_6HR = 1
    }

    /// Convenience accessor for the pump-displayed IOB in milliunits.
    public var pumpDisplayedIOB: UInt32 {
        switch type {
        case .MUDALIAR?:
            return mudaliarIOB
        case .SWAN_6HR?:
            return swan6hrIOB
        default:
            return max(mudaliarIOB, swan6hrIOB)
        }
    }
}
