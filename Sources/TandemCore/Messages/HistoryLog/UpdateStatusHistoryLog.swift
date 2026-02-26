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
        metadataAndVersionStatus = Bytes.readShort(cargo, 10)
        swUpdateStatus = Bytes.readShort(cargo, 12)
        fileDlAndSideloadStatus = Bytes.readShort(cargo, 14)
        fullDlAndCrcStatus = Bytes.readShort(cargo, 16)
        updateSuccessful = Int(cargo[19])
        externalFlashStatus = Bytes.readShort(cargo, 20)
        swPartNum = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }
}
