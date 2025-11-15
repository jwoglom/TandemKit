import Foundation

/// Request pump configuration settings.
public class PumpSettingsRequest: Message {
    public static let props = MessageProps(
        opCode: 82,
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

/// Response with basic pump settings and status information.
public class PumpSettingsResponse: Message {
    public static let props = MessageProps(
        opCode: 83,
        size: 9,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var lowInsulinThreshold: Int
    public var cannulaPrimeSize: Int
    public var autoShutdownEnabled: Int
    public var autoShutdownDuration: Int
    public var featureLock: Int
    public var oledTimeout: Int
    public var status: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        lowInsulinThreshold = Int(cargo[0])
        cannulaPrimeSize = Int(cargo[1])
        autoShutdownEnabled = Int(cargo[2])
        autoShutdownDuration = Bytes.readShort(cargo, 3)
        featureLock = Int(cargo[5])
        oledTimeout = Int(cargo[6])
        status = Bytes.readShort(cargo, 7)
    }

    public init(
        lowInsulinThreshold: Int,
        cannulaPrimeSize: Int,
        autoShutdownEnabled: Int,
        autoShutdownDuration: Int,
        featureLock: Int,
        oledTimeout: Int,
        status: Int
    ) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(lowInsulinThreshold),
            Bytes.firstByteLittleEndian(cannulaPrimeSize),
            Bytes.firstByteLittleEndian(autoShutdownEnabled),
            Bytes.firstTwoBytesLittleEndian(autoShutdownDuration),
            Bytes.firstByteLittleEndian(featureLock),
            Bytes.firstByteLittleEndian(oledTimeout),
            Bytes.firstTwoBytesLittleEndian(status)
        )
        self.lowInsulinThreshold = lowInsulinThreshold
        self.cannulaPrimeSize = cannulaPrimeSize
        self.autoShutdownEnabled = autoShutdownEnabled
        self.autoShutdownDuration = autoShutdownDuration
        self.featureLock = featureLock
        self.oledTimeout = oledTimeout
        self.status = status
    }
}
