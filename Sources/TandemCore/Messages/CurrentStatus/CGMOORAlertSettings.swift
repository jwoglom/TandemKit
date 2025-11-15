import Foundation

/// Request out-of-range CGM alert settings from the pump.
public class CGMOORAlertSettingsRequest: Message {
    public static let props = MessageProps(
        opCode: 94,
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

/// Response describing out-of-range CGM alert configuration.
public class CGMOORAlertSettingsResponse: Message {
    public static let props = MessageProps(
        opCode: 95,
        size: 3,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var sensorTimeoutAlertThreshold: Int
    public var sensorTimeoutAlertEnabled: Int
    public var sensorTimeoutDefaultBitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        sensorTimeoutAlertThreshold = Int(cargo[0])
        sensorTimeoutAlertEnabled = Int(cargo[1])
        sensorTimeoutDefaultBitmask = Int(cargo[2])
    }

    public init(sensorTimeoutAlertThreshold: Int, sensorTimeoutAlertEnabled: Int, sensorTimeoutDefaultBitmask: Int) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(sensorTimeoutAlertThreshold),
            Bytes.firstByteLittleEndian(sensorTimeoutAlertEnabled),
            Bytes.firstByteLittleEndian(sensorTimeoutDefaultBitmask)
        )
        self.sensorTimeoutAlertThreshold = sensorTimeoutAlertThreshold
        self.sensorTimeoutAlertEnabled = sensorTimeoutAlertEnabled
        self.sensorTimeoutDefaultBitmask = sensorTimeoutDefaultBitmask
    }
}
