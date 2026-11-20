import Foundation

/// Temporary adjustment (temp basal rate or temp control rate) activated. Tandem name LID_TEMP_ADJUSTMENT_ACTIVATED.
///
/// Mirrors pumpX2's `TempAdjustmentActivatedHistoryLog`.
public class TempAdjustmentActivatedHistoryLog: HistoryLog {
    public static let typeId = 565

    /// Requested percent.
    public let requestedPercent: Int
    /// Temp basal percent.
    public let tempBasalPercent: Int
    /// Duration, in milliseconds.
    public let duration: UInt32
    /// Raw requested adjustment type, see `RequestedAdjustmentType`.
    public let requestedAdjustmentType: Int
    /// The temp rate ID.
    public let tempRateId: Int

    public required init(cargo: Data) {
        requestedPercent = Bytes.readShort(cargo, 10)
        tempBasalPercent = Bytes.readShort(cargo, 12)
        duration = Bytes.readUint32(cargo, 18)
        requestedAdjustmentType = Bytes.readShort(cargo, 22)
        tempRateId = Bytes.readShort(cargo, 24)
        super.init(cargo: cargo)
    }

    public convenience init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        self.init(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, requestedPercent: 0, tempBasalPercent: 0, duration: 0, requestedAdjustmentType: 0, tempRateId: 0)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        requestedPercent: Int,
        tempBasalPercent: Int,
        duration: UInt32,
        requestedAdjustmentType: Int,
        tempRateId: Int
    ) {
        let payload = TempAdjustmentActivatedHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            requestedPercent: requestedPercent,
            tempBasalPercent: tempBasalPercent,
            duration: duration,
            requestedAdjustmentType: requestedAdjustmentType,
            tempRateId: tempRateId
        )
        self.requestedPercent = requestedPercent
        self.tempBasalPercent = tempBasalPercent
        self.duration = duration
        self.requestedAdjustmentType = requestedAdjustmentType
        self.tempRateId = tempRateId
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, requestedPercent: 0, tempBasalPercent: 0, duration: 0, requestedAdjustmentType: 0, tempRateId: 0)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        requestedPercent: Int,
        tempBasalPercent: Int,
        duration: UInt32,
        requestedAdjustmentType: Int,
        tempRateId: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(requestedPercent),
                Bytes.firstTwoBytesLittleEndian(tempBasalPercent),
                Data([0, 0, 0, 0]),
                Bytes.toUint32(duration),
                Bytes.firstTwoBytesLittleEndian(requestedAdjustmentType),
                Bytes.firstTwoBytesLittleEndian(tempRateId)
            )
        )
    }

    public enum RequestedAdjustmentType: Int {
        case TEMP_BASAL_RATE_GUI = 0
        case UNUSED_OBE = 1
        case TEMP_BASAL_RATE_BLE = 2
        case TEMP_CONTROL_RATE_BLE = 3

        public static func fromId(_ id: Int) -> RequestedAdjustmentType? {
            RequestedAdjustmentType(rawValue: id)
        }
    }

    public var requestedAdjustmentTypeEnum: RequestedAdjustmentType? {
        RequestedAdjustmentType.fromId(requestedAdjustmentType)
    }

    override public var description: String {
        "TempAdjustmentActivatedHistoryLog(cargo=\(cargo.hexadecimalString), requestedPercent=\(requestedPercent), tempBasalPercent=\(tempBasalPercent), duration=\(duration), requestedAdjustmentType=\(requestedAdjustmentType), tempRateId=\(tempRateId))"
    }
}
