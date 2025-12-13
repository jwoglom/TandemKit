import Foundation

/// History log entry capturing arm initialization metadata.
public class ArmInitHistoryLog: HistoryLog {
    public static let typeId = 99

    public let version: UInt32
    public let configABits: UInt32
    public let configBBits: UInt32
    public let numLogEntries: UInt32

    public required init(cargo: Data) {
        version = Bytes.readUint32(cargo, 10)
        configABits = Bytes.readUint32(cargo, 14)
        configBBits = Bytes.readUint32(cargo, 18)
        numLogEntries = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, version: UInt32, configABits: UInt32, configBBits: UInt32, numLogEntries: UInt32) {
        let payload = ArmInitHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            version: version,
            configABits: configABits,
            configBBits: configBBits,
            numLogEntries: numLogEntries
        )
        self.version = version
        self.configABits = configABits
        self.configBBits = configBBits
        self.numLogEntries = numLogEntries
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        version: UInt32,
        configABits: UInt32,
        configBBits: UInt32,
        numLogEntries: UInt32
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(version),
                Bytes.toUint32(configABits),
                Bytes.toUint32(configBBits),
                Bytes.toUint32(numLogEntries)
            )
        )
    }
}

public extension ArmInitHistoryLog {
    var description: String {
        "ArmInitHistoryLog(cargo=\(cargo.hexadecimalString), version=\(version), configABits=\(configABits), configBBits=\(configBBits), numLogEntries=\(numLogEntries))"
    }
}
