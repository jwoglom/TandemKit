import Foundation

/// Written for every max hourly basal limit set, even to the current value (jwoglom/pumpX2#150). Provisional name.
/// Values are milliunits per hour.
public class MaxBasalLimitSetHistoryLog: HistoryLog {
    public static let typeId = 274

    public let maxHourlyBasalMilliunits: UInt32
    public let previousMaxHourlyBasalMilliunits: UInt32

    public required init(cargo: Data) {
        maxHourlyBasalMilliunits = Bytes.readUint32(cargo, 10)
        previousMaxHourlyBasalMilliunits = Bytes.readUint32(cargo, 14)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, maxHourlyBasalMilliunits: UInt32, previousMaxHourlyBasalMilliunits: UInt32) {
        let payload = MaxBasalLimitSetHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            maxHourlyBasalMilliunits: maxHourlyBasalMilliunits,
            previousMaxHourlyBasalMilliunits: previousMaxHourlyBasalMilliunits
        )
        self.maxHourlyBasalMilliunits = maxHourlyBasalMilliunits
        self.previousMaxHourlyBasalMilliunits = previousMaxHourlyBasalMilliunits
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, maxHourlyBasalMilliunits: UInt32, previousMaxHourlyBasalMilliunits: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(maxHourlyBasalMilliunits),
                Bytes.toUint32(previousMaxHourlyBasalMilliunits)
            )
        )
    }

    public var description: String {
        "MaxBasalLimitSetHistoryLog(cargo=\(cargo.hexadecimalString), maxHourlyBasalMilliunits=\(maxHourlyBasalMilliunits), previousMaxHourlyBasalMilliunits=\(previousMaxHourlyBasalMilliunits))"
    }
}
