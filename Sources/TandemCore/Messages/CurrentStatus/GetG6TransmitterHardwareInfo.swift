import Foundation

/// Request Dexcom G6 transmitter hardware info.
public class GetG6TransmitterHardwareInfoRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-60)),
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

/// Response containing Dexcom G6 transmitter hardware info.
public class GetG6TransmitterHardwareInfoResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-59)),
        size: 96,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var transmitterFirmwareVersion: String
    public var transmitterHardwareRevision: String
    public var transmitterBleHardwareId: String
    public var transmitterSoftwareNumber: String
    public var unusedRemaining: Data

    public required init(cargo: Data) {
        self.cargo = cargo
        transmitterFirmwareVersion = Bytes.readString(cargo, 0, 16)
        transmitterHardwareRevision = Bytes.readString(cargo, 16, 16)
        transmitterBleHardwareId = Bytes.readString(cargo, 32, 16)
        transmitterSoftwareNumber = Bytes.readString(cargo, 48, 16)
        unusedRemaining = Bytes.dropFirstN(cargo, 64)
    }

    public init(
        transmitterFirmwareVersion: String,
        transmitterHardwareRevision: String,
        transmitterBleHardwareId: String,
        transmitterSoftwareNumber: String
    ) {
        cargo = Bytes.combine(
            Bytes.writeString(transmitterFirmwareVersion, 16),
            Bytes.writeString(transmitterHardwareRevision, 16),
            Bytes.writeString(transmitterBleHardwareId, 16),
            Bytes.writeString(transmitterSoftwareNumber, 16),
            Bytes.emptyBytes(32)
        )
        self.transmitterFirmwareVersion = transmitterFirmwareVersion
        self.transmitterHardwareRevision = transmitterHardwareRevision
        self.transmitterBleHardwareId = transmitterBleHardwareId
        self.transmitterSoftwareNumber = transmitterSoftwareNumber
        unusedRemaining = Bytes.emptyBytes(32)
    }
}
