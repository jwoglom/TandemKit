import Foundation

/// Synchronous dose complete (AIQ / AIDANET algorithm). Tandem name LID_SYNC_DOSE_COMPLETE.
///
/// Mirrors pumpX2's `SyncDoseCompleteHistoryLog`.
public class SyncDoseCompleteHistoryLog: HistoryLog {
    public static let typeId = 559

    /// The dose ID.
    public let doseId: Int
    /// Raw dose source, see `SyncDoseStartHistoryLog.DoseSource`.
    public let doseSource: Int
    /// Temporary adjustment percent (100 = 100%).
    public let tempAdjustmentPercent: Int
    /// Delivered dose size, in units.
    public let syncDoseSizeDelivered: Float
    /// Current basal rate, in milliunits/hr.
    public let currentBasalRate: Int
    /// Active insulin (IOB), in units.
    public let activeInsulin: Float

    public required init(cargo: Data) {
        doseId = Bytes.readShort(cargo, 10)
        doseSource = Int(cargo[cargo.startIndex + 12])
        tempAdjustmentPercent = Int(cargo[cargo.startIndex + 13])
        syncDoseSizeDelivered = Bytes.readFloat(cargo, 14)
        currentBasalRate = Bytes.readShort(cargo, 18)
        activeInsulin = Bytes.readFloat(cargo, 22)
        super.init(cargo: cargo)
    }

    public convenience init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        self.init(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, doseId: 0, doseSource: 0, tempAdjustmentPercent: 0, syncDoseSizeDelivered: 0, currentBasalRate: 0, activeInsulin: 0)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        doseId: Int,
        doseSource: Int,
        tempAdjustmentPercent: Int,
        syncDoseSizeDelivered: Float,
        currentBasalRate: Int,
        activeInsulin: Float
    ) {
        let payload = SyncDoseCompleteHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            doseId: doseId,
            doseSource: doseSource,
            tempAdjustmentPercent: tempAdjustmentPercent,
            syncDoseSizeDelivered: syncDoseSizeDelivered,
            currentBasalRate: currentBasalRate,
            activeInsulin: activeInsulin
        )
        self.doseId = doseId
        self.doseSource = doseSource
        self.tempAdjustmentPercent = tempAdjustmentPercent
        self.syncDoseSizeDelivered = syncDoseSizeDelivered
        self.currentBasalRate = currentBasalRate
        self.activeInsulin = activeInsulin
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, doseId: 0, doseSource: 0, tempAdjustmentPercent: 0, syncDoseSizeDelivered: 0, currentBasalRate: 0, activeInsulin: 0)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        doseId: Int,
        doseSource: Int,
        tempAdjustmentPercent: Int,
        syncDoseSizeDelivered: Float,
        currentBasalRate: Int,
        activeInsulin: Float
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(doseId),
                Data([UInt8(doseSource & 0xFF)]),
                Data([UInt8(tempAdjustmentPercent & 0xFF)]),
                Bytes.toFloat(syncDoseSizeDelivered),
                Bytes.firstTwoBytesLittleEndian(currentBasalRate),
                Data([0, 0]),
                Bytes.toFloat(activeInsulin)
            )
        )
    }



    override public var description: String {
        "SyncDoseCompleteHistoryLog(cargo=\(cargo.hexadecimalString), doseId=\(doseId), doseSource=\(doseSource), tempAdjustmentPercent=\(tempAdjustmentPercent), syncDoseSizeDelivered=\(syncDoseSizeDelivered), currentBasalRate=\(currentBasalRate), activeInsulin=\(activeInsulin))"
    }
}
