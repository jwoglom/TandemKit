import Foundation

/// Request basal limit settings from the pump.
public class BasalLimitSettingsRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-118)),
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

/// Response containing the configured basal limits.
public class BasalLimitSettingsResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-117)),
        size: 8,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var basalLimit: UInt32
    public var basalLimitDefault: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        basalLimit = Bytes.readUint32(cargo, 0)
        basalLimitDefault = Bytes.readUint32(cargo, 4)
    }

    public init(basalLimit: UInt32, basalLimitDefault: UInt32) {
        cargo = Bytes.combine(
            Bytes.toUint32(basalLimit),
            Bytes.toUint32(basalLimitDefault)
        )
        self.basalLimit = basalLimit
        self.basalLimitDefault = basalLimitDefault
    }
}
