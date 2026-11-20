import Foundation

public class VersionInfoHistoryLog: HistoryLog {
    public static let typeId = 191

    public let version: UInt32
    public let configABits: UInt32
    public let configBBits: UInt32
    public let armCrc: Int

    public required init(cargo: Data) {
        version = Bytes.readUint32(cargo, 10)
        configABits = Bytes.readUint32(cargo, 14)
        configBBits = Bytes.readUint32(cargo, 18)
        armCrc = Bytes.readShort(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, version: UInt32, configABits: UInt32, configBBits: UInt32, armCrc: Int) {
        let payload = VersionInfoHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            version: version,
            configABits: configABits,
            configBBits: configBBits,
            armCrc: armCrc
        )
        self.version = version
        self.configABits = configABits
        self.configBBits = configBBits
        self.armCrc = armCrc
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, version: UInt32, configABits: UInt32, configBBits: UInt32, armCrc: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(version),
                Bytes.toUint32(configABits),
                Bytes.toUint32(configBBits),
                Bytes.firstTwoBytesLittleEndian(armCrc),
                Data([0, 0])
            )
        )
    }

    override public var description: String {
        "VersionInfoHistoryLog(cargo=\(cargo.hexadecimalString), version=\(version), configABits=\(configABits), configBBits=\(configBBits), armCrc=\(armCrc))"
    }
}
