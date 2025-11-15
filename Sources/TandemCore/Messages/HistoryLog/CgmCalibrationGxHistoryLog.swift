import Foundation

/// History log entry for GX CGM calibration value.
public class CgmCalibrationGxHistoryLog: HistoryLog {
    public static let typeId = 210

    public let value: Int

    public required init(cargo: Data) {
        value = Bytes.readShort(cargo, 10)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, value: Int) {
        let payload = CgmCalibrationGxHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, value: value)
        self.value = value
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, value: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(value)
            )
        )
    }
}
