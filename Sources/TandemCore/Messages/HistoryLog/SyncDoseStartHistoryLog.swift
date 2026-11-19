import Foundation

/// Synchronous dose start (AIQ / AIDANET algorithm). Tandem name LID_SYNC_DOSE_START.
///
/// Mirrors pumpX2's `SyncDoseStartHistoryLog`.
public class SyncDoseStartHistoryLog: HistoryLog {
    public static let typeId = 558

    /// The dose ID.
    public let doseId: Int
    /// Raw dose source, see `DoseSource`.
    public let doseSource: Int
    /// Temporary adjustment percent (100 = 100%).
    public let tempAdjustmentPercent: Int
    /// Requested dose size, in units.
    public let syncDoseSizeRequested: Float
    /// Current basal rate, in milliunits/hr.
    public let currentBasalRate: Int
    /// Profile basal rate, in milliunits/hr.
    public let profileBasalRate: Int
    /// Active insulin (IOB), in units.
    public let activeInsulin: Float

    public required init(cargo: Data) {
        doseId = Bytes.readShort(cargo, 10)
        doseSource = Int(cargo[cargo.startIndex + 12])
        tempAdjustmentPercent = Int(cargo[cargo.startIndex + 13])
        syncDoseSizeRequested = Bytes.readFloat(cargo, 14)
        currentBasalRate = Bytes.readShort(cargo, 18)
        profileBasalRate = Bytes.readShort(cargo, 20)
        activeInsulin = Bytes.readFloat(cargo, 22)
        super.init(cargo: cargo)
    }

    public convenience init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        self.init(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, doseId: 0, doseSource: 0, tempAdjustmentPercent: 0, syncDoseSizeRequested: 0, currentBasalRate: 0, profileBasalRate: 0, activeInsulin: 0)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        doseId: Int,
        doseSource: Int,
        tempAdjustmentPercent: Int,
        syncDoseSizeRequested: Float,
        currentBasalRate: Int,
        profileBasalRate: Int,
        activeInsulin: Float
    ) {
        let payload = SyncDoseStartHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            doseId: doseId,
            doseSource: doseSource,
            tempAdjustmentPercent: tempAdjustmentPercent,
            syncDoseSizeRequested: syncDoseSizeRequested,
            currentBasalRate: currentBasalRate,
            profileBasalRate: profileBasalRate,
            activeInsulin: activeInsulin
        )
        self.doseId = doseId
        self.doseSource = doseSource
        self.tempAdjustmentPercent = tempAdjustmentPercent
        self.syncDoseSizeRequested = syncDoseSizeRequested
        self.currentBasalRate = currentBasalRate
        self.profileBasalRate = profileBasalRate
        self.activeInsulin = activeInsulin
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, doseId: 0, doseSource: 0, tempAdjustmentPercent: 0, syncDoseSizeRequested: 0, currentBasalRate: 0, profileBasalRate: 0, activeInsulin: 0)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        doseId: Int,
        doseSource: Int,
        tempAdjustmentPercent: Int,
        syncDoseSizeRequested: Float,
        currentBasalRate: Int,
        profileBasalRate: Int,
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
                Bytes.toFloat(syncDoseSizeRequested),
                Bytes.firstTwoBytesLittleEndian(currentBasalRate),
                Bytes.firstTwoBytesLittleEndian(profileBasalRate),
                Bytes.toFloat(activeInsulin)
            )
        )
    }

    public enum DoseSource: Int {
        case SUSPENDED = 0
        case PROFILE = 1
        case PROFILE_AND_TEMP_RATE = 2
        case ALGORITHM = 3
        case ALGORITHM_AND_TEMP_CONTROL_RATE = 4

        public static func fromId(_ id: Int) -> DoseSource? {
            DoseSource(rawValue: id)
        }
    }

    public var doseSourceEnum: DoseSource? {
        DoseSource.fromId(doseSource)
    }

    override public var description: String {
        "SyncDoseStartHistoryLog(cargo=\(cargo.hexadecimalString), doseId=\(doseId), doseSource=\(doseSource), tempAdjustmentPercent=\(tempAdjustmentPercent), syncDoseSizeRequested=\(syncDoseSizeRequested), currentBasalRate=\(currentBasalRate), profileBasalRate=\(profileBasalRate), activeInsulin=\(activeInsulin))"
    }
}
