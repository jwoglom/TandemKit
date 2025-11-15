import Foundation

/// Request the pump software and hardware version information.
public class PumpVersionRequest: Message {
    public static let props = MessageProps(
        opCode: 84,
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

/// Response containing version information for the pump.
public class PumpVersionResponse: Message {
    public static let props = MessageProps(
        opCode: 85,
        size: 48,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var armSwVer: UInt32
    public var mspSwVer: UInt32
    public var configABits: UInt32
    public var configBBits: UInt32
    public var serialNum: UInt32
    public var partNum: UInt32
    public var pumpRev: String
    public var pcbaSN: UInt32
    public var pcbaRev: String
    public var modelNum: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        armSwVer = Bytes.readUint32(cargo, 0)
        mspSwVer = Bytes.readUint32(cargo, 4)
        configABits = Bytes.readUint32(cargo, 8)
        configBBits = Bytes.readUint32(cargo, 12)
        serialNum = Bytes.readUint32(cargo, 16)
        partNum = Bytes.readUint32(cargo, 20)
        pumpRev = Bytes.readString(cargo, 24, 8)
        pcbaSN = Bytes.readUint32(cargo, 32)
        pcbaRev = Bytes.readString(cargo, 36, 8)
        modelNum = Bytes.readUint32(cargo, 44)
    }

    public init(
        armSwVer: UInt32,
        mspSwVer: UInt32,
        configABits: UInt32,
        configBBits: UInt32,
        serialNum: UInt32,
        partNum: UInt32,
        pumpRev: String,
        pcbaSN: UInt32,
        pcbaRev: String,
        modelNum: UInt32
    ) {
        cargo = Bytes.combine(
            Bytes.toUint32(armSwVer),
            Bytes.toUint32(mspSwVer),
            Bytes.toUint32(configABits),
            Bytes.toUint32(configBBits),
            Bytes.toUint32(serialNum),
            Bytes.toUint32(partNum),
            Bytes.writeString(pumpRev, 8),
            Bytes.toUint32(pcbaSN),
            Bytes.writeString(pcbaRev, 8),
            Bytes.toUint32(modelNum)
        )
        self.armSwVer = armSwVer
        self.mspSwVer = mspSwVer
        self.configABits = configABits
        self.configBBits = configBBits
        self.serialNum = serialNum
        self.partNum = partNum
        self.pumpRev = pumpRev
        self.pcbaSN = pcbaSN
        self.pcbaRev = pcbaRev
        self.modelNum = modelNum
    }
}
