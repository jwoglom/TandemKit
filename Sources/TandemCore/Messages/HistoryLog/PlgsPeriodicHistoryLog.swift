import Foundation

/// History log marker used by PLGS periodic events.
public class PlgsPeriodicHistoryLog: HistoryLog {
    public static let typeId = 140

    public required init(cargo: Data) {
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        let payload = PlgsPeriodicHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum)
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum)
            )
        )
    }
}

public extension PlgsPeriodicHistoryLog {
    var description: String {
        "PlgsPeriodicHistoryLog(cargo=\(cargo.hexadecimalString))"
    }
}
