import Foundation

public class CannulaFilledHistoryLog: HistoryLog {
    public static let typeId = 61

    /// The number of units used to prime the cannula.
    public let primeSize: Float

    public required init(cargo: Data) {
        primeSize = Bytes.readFloat(cargo, 10)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, primeSize: Float) {
        let payload = CannulaFilledHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, primeSize: primeSize)
        self.primeSize = primeSize
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, primeSize: Float) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toFloat(primeSize)
            )
        )
    }
}
