import Foundation

/// Written for every max bolus limit set, even to the current value (jwoglom/pumpX2#150). Provisional name.
/// Values are milliunits.
public class MaxBolusLimitSetHistoryLog: HistoryLog {
    public static let typeId = 326

    public let maxBolusMilliunits: Int
    public let previousMaxBolusMilliunits: Int

    public required init(cargo: Data) {
        maxBolusMilliunits = Bytes.readShort(cargo, 10)
        previousMaxBolusMilliunits = Bytes.readShort(cargo, 12)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, maxBolusMilliunits: Int, previousMaxBolusMilliunits: Int) {
        let payload = MaxBolusLimitSetHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            maxBolusMilliunits: maxBolusMilliunits,
            previousMaxBolusMilliunits: previousMaxBolusMilliunits
        )
        self.maxBolusMilliunits = maxBolusMilliunits
        self.previousMaxBolusMilliunits = previousMaxBolusMilliunits
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, maxBolusMilliunits: Int, previousMaxBolusMilliunits: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(maxBolusMilliunits),
                Bytes.firstTwoBytesLittleEndian(previousMaxBolusMilliunits)
            )
        )
    }

    override public var description: String {
        "MaxBolusLimitSetHistoryLog(cargo=\(cargo.hexadecimalString), maxBolusMilliunits=\(maxBolusMilliunits), previousMaxBolusMilliunits=\(previousMaxBolusMilliunits))"
    }
}
