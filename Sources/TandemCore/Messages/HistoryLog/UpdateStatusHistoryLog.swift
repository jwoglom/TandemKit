import Foundation

/// History log entry summarizing software update status.
public class UpdateStatusHistoryLog: HistoryLog {
    public static let typeId = 203

    public let swUpdateStatus: Int
    public let metadataAndVersionStatus: Int
    public let fullDlAndCrcStatus: Int
    public let fileDlAndSideloadStatus: Int
    public let externalFlashStatus: Int
    public let updateSuccessful: Int
    public let swPartNum: UInt32

    public required init(cargo: Data) {
        metadataAndVersionStatus = Int(Bytes.readShort(cargo, 10))
        swUpdateStatus = Int(Bytes.readShort(cargo, 12))
        fileDlAndSideloadStatus = Int(Bytes.readShort(cargo, 14))
        fullDlAndCrcStatus = Int(Bytes.readShort(cargo, 16))
        updateSuccessful = Int(cargo[19])
        externalFlashStatus = Int(Bytes.readShort(cargo, 20))
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
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(metadataAndVersionStatus),
                Bytes.firstTwoBytesLittleEndian(swUpdateStatus),
                Bytes.firstTwoBytesLittleEndian(fileDlAndSideloadStatus),
                Bytes.firstTwoBytesLittleEndian(fullDlAndCrcStatus),
                Data([0, UInt8(updateSuccessful & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(externalFlashStatus),
                Bytes.toUint32(swPartNum)
            )
        )
    }
}

public extension UpdateStatusHistoryLog {
    var description: String {
        "UpdateStatusHistoryLog(cargo=\(cargo.hexadecimalString), swUpdateStatus=\(swUpdateStatus), metadataAndVersionStatus=\(metadataAndVersionStatus), fullDlAndCrcStatus=\(fullDlAndCrcStatus), fileDlAndSideloadStatus=\(fileDlAndSideloadStatus), externalFlashStatus=\(externalFlashStatus), updateSuccessful=\(updateSuccessful), swPartNum=\(swPartNum))"
    }
}
