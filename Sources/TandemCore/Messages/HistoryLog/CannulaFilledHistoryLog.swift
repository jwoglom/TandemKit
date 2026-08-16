import Foundation

public class CannulaFilledHistoryLog: HistoryLog {
    public static let typeId = 61

    /// The number of units used to prime the cannula.
    public let primeSize: Float
    public let completionStatusRaw: UInt32

    public required init(cargo: Data) {
        primeSize = Bytes.readFloat(cargo, 10)
        completionStatusRaw = Bytes.readUint32(cargo, 14)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, primeSize: Float, completionStatus: UInt32) {
        let payload = CannulaFilledHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, primeSize: primeSize, completionStatus: completionStatus)
        self.primeSize = primeSize
        self.completionStatusRaw = completionStatus
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, primeSize: Float, completionStatus: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toFloat(primeSize),
                Bytes.toUint32(completionStatus)
            )
        )
    }

    public enum CompletionStatus: Int {
        case userAborted = 0
        case terminatedByAlarm = 1
        case terminatedByMalfunction = 2
        case completed = 3
    }

    public var completionStatus: CompletionStatus? {
        CompletionStatus(rawValue: Int(completionStatusRaw))
    }

    public var description: String {
        "CannulaFilledHistoryLog(cargo=\(cargo.hexadecimalString), primeSize=\(primeSize), completionStatusRaw=\(completionStatusRaw))"
    }
}
