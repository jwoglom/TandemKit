import Foundation

/// Request CGM glucose alert settings from the pump.
public class CGMGlucoseAlertSettingsRequest: Message {
    public static let props = MessageProps(
        opCode: 90,
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

/// Response containing CGM glucose alert configuration.
public class CGMGlucoseAlertSettingsResponse: Message {
    public static let props = MessageProps(
        opCode: 91,
        size: 12,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var highGlucoseAlertThreshold: Int
    public var highGlucoseAlertEnabled: Int
    public var highGlucoseRepeatDuration: Int
    public var highGlucoseAlertDefaultBitmask: Int
    public var lowGlucoseAlertThreshold: Int
    public var lowGlucoseAlertEnabled: Int
    public var lowGlucoseRepeatDuration: Int
    public var lowGlucoseAlertDefaultBitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        highGlucoseAlertThreshold = Bytes.readShort(cargo, 0)
        highGlucoseAlertEnabled = Int(cargo[2])
        highGlucoseRepeatDuration = Bytes.readShort(cargo, 3)
        highGlucoseAlertDefaultBitmask = Int(cargo[5])
        lowGlucoseAlertThreshold = Bytes.readShort(cargo, 6)
        lowGlucoseAlertEnabled = Int(cargo[8])
        lowGlucoseRepeatDuration = Bytes.readShort(cargo, 9)
        lowGlucoseAlertDefaultBitmask = Int(cargo[11])
    }

    public init(
        highGlucoseAlertThreshold: Int,
        highGlucoseAlertEnabled: Int,
        highGlucoseRepeatDuration: Int,
        highGlucoseAlertDefaultBitmask: Int,
        lowGlucoseAlertThreshold: Int,
        lowGlucoseAlertEnabled: Int,
        lowGlucoseRepeatDuration: Int,
        lowGlucoseAlertDefaultBitmask: Int
    ) {
        cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(highGlucoseAlertThreshold),
            Bytes.firstByteLittleEndian(highGlucoseAlertEnabled),
            Bytes.firstTwoBytesLittleEndian(highGlucoseRepeatDuration),
            Bytes.firstByteLittleEndian(highGlucoseAlertDefaultBitmask),
            Bytes.firstTwoBytesLittleEndian(lowGlucoseAlertThreshold),
            Bytes.firstByteLittleEndian(lowGlucoseAlertEnabled),
            Bytes.firstTwoBytesLittleEndian(lowGlucoseRepeatDuration),
            Bytes.firstByteLittleEndian(lowGlucoseAlertDefaultBitmask)
        )
        self.highGlucoseAlertThreshold = highGlucoseAlertThreshold
        self.highGlucoseAlertEnabled = highGlucoseAlertEnabled
        self.highGlucoseRepeatDuration = highGlucoseRepeatDuration
        self.highGlucoseAlertDefaultBitmask = highGlucoseAlertDefaultBitmask
        self.lowGlucoseAlertThreshold = lowGlucoseAlertThreshold
        self.lowGlucoseAlertEnabled = lowGlucoseAlertEnabled
        self.lowGlucoseRepeatDuration = lowGlucoseRepeatDuration
        self.lowGlucoseAlertDefaultBitmask = lowGlucoseAlertDefaultBitmask
    }
}
