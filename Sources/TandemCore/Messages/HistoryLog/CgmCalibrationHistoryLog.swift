import Foundation

/// History log entry recording a CGM calibration event.
public class CgmCalibrationHistoryLog: HistoryLog {
    public static let typeId = 160

    public let currentTime: UInt32
    public let timestamp: UInt32
    public let calTimestamp: UInt32
    public let value: Int
    public let currentDisplayValue: Int

    public required init(cargo: Data) {
        currentTime = Bytes.readUint32(cargo, 10)
        timestamp = Bytes.readUint32(cargo, 14)
        calTimestamp = Bytes.readUint32(cargo, 18)
        value = Bytes.readShort(cargo, 22)
        currentDisplayValue = Bytes.readShort(cargo, 24)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        currentTime: UInt32,
        timestamp: UInt32,
        calTimestamp: UInt32,
        value: Int,
        currentDisplayValue: Int
    ) {
        let payload = CgmCalibrationHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            currentTime: currentTime,
            timestamp: timestamp,
            calTimestamp: calTimestamp,
            value: value,
            currentDisplayValue: currentDisplayValue
        )
        self.currentTime = currentTime
        self.timestamp = timestamp
        self.calTimestamp = calTimestamp
        self.value = value
        self.currentDisplayValue = currentDisplayValue
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        currentTime: UInt32,
        timestamp: UInt32,
        calTimestamp: UInt32,
        value: Int,
        currentDisplayValue: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(currentTime),
                Bytes.toUint32(timestamp),
                Bytes.toUint32(calTimestamp),
                Bytes.firstTwoBytesLittleEndian(value),
                Bytes.firstTwoBytesLittleEndian(currentDisplayValue)
            )
        )
    }
}
