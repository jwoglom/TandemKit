import Foundation

/// History log marker for Dexcom G7 CGM stop session events.
public class CgmStopSessionG7HistoryLog: HistoryLog {
    public static let typeId = 447

    public required init(cargo: Data) {
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        let payload = CgmStopSessionG7HistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum)
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), UInt8((typeId >> 8) & 0xFF)]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum)
            )
        )
    }
}

public extension CgmStopSessionG7HistoryLog {
    var description: String {
        "CgmStopSessionG7HistoryLog(cargo=\(cargo.hexadecimalString))"
    }
}
