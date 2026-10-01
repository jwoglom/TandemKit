import Foundation

public class CannulaFilledHistoryLog: HistoryLog {
    public static let typeId = 61

    /// The number of units used to prime the cannula.
    public let primeSize: Float
    public let completionStatusRaw: UInt32
    /// Raw infusion set type, see `InfusionSetType`.
    public let infusionSetTypeRaw: Int

    public required init(cargo: Data) {
        primeSize = Bytes.readFloat(cargo, 10)
        completionStatusRaw = Bytes.readUint32(cargo, 14)
        infusionSetTypeRaw = Int(cargo[cargo.startIndex + 18])
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, primeSize: Float, completionStatus: UInt32, infusionSetType: Int = 0) {
        let payload = CannulaFilledHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, primeSize: primeSize, completionStatus: completionStatus, infusionSetType: infusionSetType)
        self.primeSize = primeSize
        self.completionStatusRaw = completionStatus
        self.infusionSetTypeRaw = infusionSetType
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, primeSize: Float, completionStatus: UInt32, infusionSetType: Int = 0) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toFloat(primeSize),
                Bytes.toUint32(completionStatus),
                Data([UInt8(infusionSetType & 0xFF)])
            )
        )
    }

    public enum CompletionStatus: Int {
        case userAborted = 0
        case terminatedByAlarm = 1
        case terminatedByMalfunction = 2
        case completed = 3
    }

    public enum InfusionSetType: Int {
        case defaultTubed = 0
        case tubed = 1
        case tubeless = 2
    }

    public var infusionSetType: InfusionSetType? {
        InfusionSetType(rawValue: infusionSetTypeRaw)
    }

    public var completionStatus: CompletionStatus? {
        CompletionStatus(rawValue: Int(completionStatusRaw))
    }

    public var description: String {
        "CannulaFilledHistoryLog(cargo=\(cargo.hexadecimalString), primeSize=\(primeSize), completionStatusRaw=\(completionStatusRaw), infusionSetTypeRaw=\(infusionSetTypeRaw))"
    }
}
