import Foundation

/// Request CGM rate-of-change alert settings from the pump.
public class CGMRateAlertSettingsRequest: Message {
    public static let props = MessageProps(
        opCode: 92,
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

/// Response describing rate-of-change CGM alert configuration.
public class CGMRateAlertSettingsResponse: Message {
    public static let props = MessageProps(
        opCode: 93,
        size: 6,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var riseRateThreshold: Int
    public var riseRateEnabled: Int
    public var riseRateDefaultBitmask: Int
    public var fallRateThreshold: Int
    public var fallRateEnabled: Int
    public var fallRateDefaultBitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        riseRateThreshold = Int(cargo[0])
        riseRateEnabled = Int(cargo[1])
        riseRateDefaultBitmask = Int(cargo[2])
        fallRateThreshold = Int(cargo[3])
        fallRateEnabled = Int(cargo[4])
        fallRateDefaultBitmask = Int(cargo[5])
    }

    public init(
        riseRateThreshold: Int,
        riseRateEnabled: Int,
        riseRateDefaultBitmask: Int,
        fallRateThreshold: Int,
        fallRateEnabled: Int,
        fallRateDefaultBitmask: Int
    ) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(riseRateThreshold),
            Bytes.firstByteLittleEndian(riseRateEnabled),
            Bytes.firstByteLittleEndian(riseRateDefaultBitmask),
            Bytes.firstByteLittleEndian(fallRateThreshold),
            Bytes.firstByteLittleEndian(fallRateEnabled),
            Bytes.firstByteLittleEndian(fallRateDefaultBitmask)
        )
        self.riseRateThreshold = riseRateThreshold
        self.riseRateEnabled = riseRateEnabled
        self.riseRateDefaultBitmask = riseRateDefaultBitmask
        self.fallRateThreshold = fallRateThreshold
        self.fallRateEnabled = fallRateEnabled
        self.fallRateDefaultBitmask = fallRateDefaultBitmask
    }
}
