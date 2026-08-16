import Foundation

public class CgmDataFsl3HistoryLog: HistoryLog {
    public static let typeId = 480

    public let status: Int
    public let type: Int
    public let rate: Int
    public let rssi: Int
    public let value: Int
    public let timestamp: UInt32
    public let transmitterTimestamp: UInt32

    public required init(cargo: Data) {
        status = Bytes.readShort(cargo, 10)
        type = Int(cargo[12])
        rate = Int(Int8(bitPattern: cargo[13]))
        rssi = Int(Int8(bitPattern: cargo[15]))
        value = Bytes.readShort(cargo, 16)
        timestamp = Bytes.readUint32(cargo, 18)
        transmitterTimestamp = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public convenience init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        self.init(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, status: 0, type: 0, rate: 0, rssi: 0, value: 0, timestamp: 0, transmitterTimestamp: 0)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        status: Int,
        type: Int,
        rate: Int,
        rssi: Int,
        value: Int,
        timestamp: UInt32,
        transmitterTimestamp: UInt32
    ) {
        let payload = CgmDataFsl3HistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            status: status,
            type: type,
            rate: rate,
            rssi: rssi,
            value: value,
            timestamp: timestamp,
            transmitterTimestamp: transmitterTimestamp
        )
        self.status = status
        self.type = type
        self.rate = rate
        self.rssi = rssi
        self.value = value
        self.timestamp = timestamp
        self.transmitterTimestamp = transmitterTimestamp
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, status: 0, type: 0, rate: 0, rssi: 0, value: 0, timestamp: 0, transmitterTimestamp: 0)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        status: Int,
        type: Int,
        rate: Int,
        rssi: Int,
        value: Int,
        timestamp: UInt32,
        transmitterTimestamp: UInt32
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(status),
                Data([UInt8(type & 0xFF)]),
                Data([UInt8(rate & 0xFF)]),
                Data([0]),
                Data([UInt8(rssi & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(value),
                Bytes.toUint32(timestamp),
                Bytes.toUint32(transmitterTimestamp)
            )
        )
    }
}
