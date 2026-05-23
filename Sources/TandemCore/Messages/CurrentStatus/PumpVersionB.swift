import Foundation

/// Request alternative pump version information.
public class PumpVersionBRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-124)),
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
        "PumpVersionBRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response with alternative pump version information.
///
/// Binary layout (60 bytes):
///   bytes  0-19: softwareName (20-char string)
///   bytes 20-23: configurationBitsA (uint32)
///   bytes 24-27: configurationBitsB (uint32)
///   bytes 28-31: serialNumber (uint32)
///   bytes 32-35: modelNumber (uint32)
///   bytes 36-43: pumpRevision (8-char string)
///   bytes 44-47: pcbPartNumberA (uint32)
///   bytes 48-51: pcbSerialNumberA (uint32)
///   bytes 52-59: pcbRevisionNumberA (8-char string)
public class PumpVersionBResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-123)),
        size: 60,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var softwareName: String
    public var configurationBitsA: UInt32
    public var configurationBitsB: UInt32
    public var serialNumber: UInt32
    public var modelNumber: UInt32
    public var pumpRevision: String
    public var pcbPartNumberA: UInt32
    public var pcbSerialNumberA: UInt32
    public var pcbRevisionNumberA: String

    public required init(cargo: Data) {
        self.cargo = cargo
        softwareName = Bytes.readString(cargo, 0, 20)
        configurationBitsA = Bytes.readUint32(cargo, 20)
        configurationBitsB = Bytes.readUint32(cargo, 24)
        serialNumber = Bytes.readUint32(cargo, 28)
        modelNumber = Bytes.readUint32(cargo, 32)
        pumpRevision = Bytes.readString(cargo, 36, 8)
        pcbPartNumberA = Bytes.readUint32(cargo, 44)
        pcbSerialNumberA = Bytes.readUint32(cargo, 48)
        pcbRevisionNumberA = Bytes.readString(cargo, 52, 8)
    }

    public init(
        softwareName: String,
        configurationBitsA: UInt32,
        configurationBitsB: UInt32,
        serialNumber: UInt32,
        modelNumber: UInt32,
        pumpRevision: String,
        pcbPartNumberA: UInt32,
        pcbSerialNumberA: UInt32,
        pcbRevisionNumberA: String
    ) {
        cargo = Bytes.combine(
            Bytes.writeString(softwareName, 20),
            Bytes.toUint32(configurationBitsA),
            Bytes.toUint32(configurationBitsB),
            Bytes.toUint32(serialNumber),
            Bytes.toUint32(modelNumber),
            Bytes.writeString(pumpRevision, 8),
            Bytes.toUint32(pcbPartNumberA),
            Bytes.toUint32(pcbSerialNumberA),
            Bytes.writeString(pcbRevisionNumberA, 8)
        )
        self.softwareName = softwareName
        self.configurationBitsA = configurationBitsA
        self.configurationBitsB = configurationBitsB
        self.serialNumber = serialNumber
        self.modelNumber = modelNumber
        self.pumpRevision = pumpRevision
        self.pcbPartNumberA = pcbPartNumberA
        self.pcbSerialNumberA = pcbSerialNumberA
        self.pcbRevisionNumberA = pcbRevisionNumberA
    }

    public var description: String {
        "PumpVersionBResponse(cargo=\(cargo.hexadecimalString), softwareName=\(softwareName), configurationBitsA=\(configurationBitsA), configurationBitsB=\(configurationBitsB), serialNumber=\(serialNumber), modelNumber=\(modelNumber), pumpRevision=\(pumpRevision), pcbPartNumberA=\(pcbPartNumberA), pcbSerialNumberA=\(pcbSerialNumberA), pcbRevisionNumberA=\(pcbRevisionNumberA))"
    }
}
