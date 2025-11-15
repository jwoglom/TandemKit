import Foundation

/// History log entry containing a CGM data sample.
public class CgmDataSampleHistoryLog: HistoryLog {
    public static let typeId = 151

    public let status: Int
    public let value: Int

    public required init(cargo: Data) {
        status = Bytes.readShort(cargo, 10)
        value = Bytes.readShort(cargo, 19)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, status: Int, value: Int) {
        let payload = CgmDataSampleHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            status: status,
            value: value
        )
        self.status = status
        self.value = value
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, status: Int, value: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(status),
                Bytes.firstTwoBytesLittleEndian(value)
            )
        )
    }
}
