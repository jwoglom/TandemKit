import Foundation

public class UpdateStatusHistoryLog: HistoryLog {
    public static let typeId = 203

    public let metadataAndVersionStatus: Int
    public let swUpdateStatus: Int
    public let fileDlAndSideloadStatus: Int
    public let fullDlAndCrcStatus: Int
    public let updateSuccessful: Int
    public let externalFlashStatus: Int
    public let swPartNum: UInt32

    public required init(cargo: Data) {
        // Layout per the Tandem Source event schema: SwUpdateStatus u16 @10, MetadataAndVersionStatus u16 @12,
        // FullDlAndCrcStatus u16 @14, FileDlAndSideloadStatus u16 @16, ExternalFlashStatus u16 @18,
        // UpdateSuccessful u8 @20, SwPartNum u32 @22.
        swUpdateStatus = Bytes.readShort(cargo, 10)
        metadataAndVersionStatus = Bytes.readShort(cargo, 12)
        fullDlAndCrcStatus = Bytes.readShort(cargo, 14)
        fileDlAndSideloadStatus = Bytes.readShort(cargo, 16)
        externalFlashStatus = Bytes.readShort(cargo, 18)
        updateSuccessful = Int(cargo[cargo.startIndex + 20])
        swPartNum = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        swUpdateStatus: Int,
        metadataAndVersionStatus: Int,
        fullDlAndCrcStatus: Int,
        fileDlAndSideloadStatus: Int,
        externalFlashStatus: Int,
        updateSuccessful: Int,
        swPartNum: UInt32
    ) {
        let payload = UpdateStatusHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            swUpdateStatus: swUpdateStatus,
            metadataAndVersionStatus: metadataAndVersionStatus,
            fullDlAndCrcStatus: fullDlAndCrcStatus,
            fileDlAndSideloadStatus: fileDlAndSideloadStatus,
            externalFlashStatus: externalFlashStatus,
            updateSuccessful: updateSuccessful,
            swPartNum: swPartNum
        )
        self.swUpdateStatus = swUpdateStatus
        self.metadataAndVersionStatus = metadataAndVersionStatus
        self.fullDlAndCrcStatus = fullDlAndCrcStatus
        self.fileDlAndSideloadStatus = fileDlAndSideloadStatus
        self.externalFlashStatus = externalFlashStatus
        self.updateSuccessful = updateSuccessful
        self.swPartNum = swPartNum
        super.init(cargo: payload)
    }

    public convenience init(
        swUpdateStatus: Int,
        metadataAndVersionStatus: Int,
        fullDlAndCrcStatus: Int,
        fileDlAndSideloadStatus: Int,
        externalFlashStatus: Int,
        updateSuccessful: Int,
        swPartNum: UInt32
    ) {
        self.init(
            pumpTimeSec: 0,
            sequenceNum: 0,
            swUpdateStatus: swUpdateStatus,
            metadataAndVersionStatus: metadataAndVersionStatus,
            fullDlAndCrcStatus: fullDlAndCrcStatus,
            fileDlAndSideloadStatus: fileDlAndSideloadStatus,
            externalFlashStatus: externalFlashStatus,
            updateSuccessful: updateSuccessful,
            swPartNum: swPartNum
        )
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        swUpdateStatus: Int,
        metadataAndVersionStatus: Int,
        fullDlAndCrcStatus: Int,
        fileDlAndSideloadStatus: Int,
        externalFlashStatus: Int,
        updateSuccessful: Int,
        swPartNum: UInt32
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(swUpdateStatus),
                Bytes.firstTwoBytesLittleEndian(metadataAndVersionStatus),
                Bytes.firstTwoBytesLittleEndian(fullDlAndCrcStatus),
                Bytes.firstTwoBytesLittleEndian(fileDlAndSideloadStatus),
                Bytes.firstTwoBytesLittleEndian(externalFlashStatus),
                Data([UInt8(truncatingIfNeeded: updateSuccessful), 0]),
                Bytes.toUint32(swPartNum)
            )
        )
    }

    /// Known values for `updateSuccessful`; see Java's `UpdateStatusHistoryLog.UpdateSuccessful`.
    public enum UpdateSuccessful: Int {
        case notSuccessful = 0
        case successful = 1
    }

    public var updateSuccessfulEnum: UpdateSuccessful? {
        UpdateSuccessful(rawValue: updateSuccessful)
    }

    public var description: String {
        "UpdateStatusHistoryLog(cargo=\(cargo.hexadecimalString), swUpdateStatus=\(swUpdateStatus), metadataAndVersionStatus=\(metadataAndVersionStatus), fullDlAndCrcStatus=\(fullDlAndCrcStatus), fileDlAndSideloadStatus=\(fileDlAndSideloadStatus), externalFlashStatus=\(externalFlashStatus), updateSuccessful=\(updateSuccessful), swPartNum=\(swPartNum))"
    }
}
