import Foundation

/// Hourly Mobi statistics, probably BLE RSSI in dBm (jwoglom/pumpX2#150). Provisional name; `unknown*` fields are unidentified.
/// Bytes 10-15 are signed; `intervalSeconds` is the period covered, about 3600.
public class BleLinkStatsHistoryLog: HistoryLog {
    public static let typeId = 473

    public let minimum: Int
    public let maximum: Int
    public let unknown12: Int
    public let unknown13: Int
    public let unknown14: Int
    public let unknown15: Int
    public let unknown16: Int
    public let unknown18: Int
    public let intervalSeconds: Int

    public required init(cargo: Data) {
        minimum = Int(Int8(bitPattern: cargo[10]))
        maximum = Int(Int8(bitPattern: cargo[11]))
        unknown12 = Int(Int8(bitPattern: cargo[12]))
        unknown13 = Int(Int8(bitPattern: cargo[13]))
        unknown14 = Int(Int8(bitPattern: cargo[14]))
        unknown15 = Int(Int8(bitPattern: cargo[15]))
        unknown16 = Bytes.readShort(cargo, 16)
        unknown18 = Bytes.readShort(cargo, 18)
        intervalSeconds = Bytes.readShort(cargo, 20)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, minimum: Int, maximum: Int, unknown12: Int, unknown13: Int, unknown14: Int, unknown15: Int, unknown16: Int, unknown18: Int, intervalSeconds: Int) {
        let payload = BleLinkStatsHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            minimum: minimum,
            maximum: maximum,
            unknown12: unknown12,
            unknown13: unknown13,
            unknown14: unknown14,
            unknown15: unknown15,
            unknown16: unknown16,
            unknown18: unknown18,
            intervalSeconds: intervalSeconds
        )
        self.minimum = minimum
        self.maximum = maximum
        self.unknown12 = unknown12
        self.unknown13 = unknown13
        self.unknown14 = unknown14
        self.unknown15 = unknown15
        self.unknown16 = unknown16
        self.unknown18 = unknown18
        self.intervalSeconds = intervalSeconds
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, minimum: Int, maximum: Int, unknown12: Int, unknown13: Int, unknown14: Int, unknown15: Int, unknown16: Int, unknown18: Int, intervalSeconds: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(minimum & 0xFF)]),
                Data([UInt8(maximum & 0xFF)]),
                Data([UInt8(unknown12 & 0xFF)]),
                Data([UInt8(unknown13 & 0xFF)]),
                Data([UInt8(unknown14 & 0xFF)]),
                Data([UInt8(unknown15 & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(unknown16),
                Bytes.firstTwoBytesLittleEndian(unknown18),
                Bytes.firstTwoBytesLittleEndian(intervalSeconds)
            )
        )
    }

    public var description: String {
        "BleLinkStatsHistoryLog(cargo=\(cargo.hexadecimalString), minimum=\(minimum), maximum=\(maximum), unknown12=\(unknown12), unknown13=\(unknown13), unknown14=\(unknown14), unknown15=\(unknown15), unknown16=\(unknown16), unknown18=\(unknown18), intervalSeconds=\(intervalSeconds))"
    }
}
