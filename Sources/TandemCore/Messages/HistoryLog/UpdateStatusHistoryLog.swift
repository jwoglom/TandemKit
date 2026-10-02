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


    /// Bits 0-7: component update succeeded; bits 8-15: component update failed (Tandem schema SwUpdateStatus).
    public enum SwUpdateStatus: Int, CaseIterable {
        case ARM_UPDATE_SUCCESS = 1
        case MSP_UPDATE_SUCCESS = 2
        case RADIO_PROCESSOR_UPDATE_SUCCESS = 4
        case ALPHAMASKS_UPDATE_SUCCESS = 8
        case RASTER_UPDATE_SUCCESS = 16
        case RADIO_APPLICATION_UPDATE_SUCCESS = 32
        case RADIO_BOOTLOADER_UPDATE_SUCCESS = 64
        case RADIO_STACK_UPDATE_SUCCESS = 128
        case ARM_UPDATE_FAILED = 256
        case MSP_UPDATE_FAILED = 512
        case RADIO_PROCESSOR_UPDATE_FAILED = 1024
        case ALPHAMASKS_UPDATE_FAILED = 2048
        case RASTER_UPDATE_FAILED = 4096
        case RADIO_APPLICATION_UPDATE_FAILED = 8192
        case RADIO_BOOTLOADER_UPDATE_FAILED = 16384
        case RADIO_STACK_UPDATE_FAILED = 32768

        public static func fromBitmask(_ bitmask: Int) -> Set<SwUpdateStatus> {
            var items = Set<SwUpdateStatus>()
            for i in SwUpdateStatus.allCases where (bitmask & i.rawValue) != 0 {
                items.insert(i)
            }
            return items
        }
    }

    public var swUpdateStatusSet: Set<SwUpdateStatus> {
        SwUpdateStatus.fromBitmask(swUpdateStatus)
    }

    /// Bits 0-7: component metadata CRC failed; bits 8-15: component version check failed (Tandem schema MetadataAndVersionStatus).
    public enum MetadataAndVersionStatus: Int, CaseIterable {
        case ARM_METADATA_CRC_FAILED = 1
        case MSP_METADATA_CRC_FAILED = 2
        case RADIO_PROCESSOR_METADATA_CRC_FAILED = 4
        case ALPHAMASKS_METADATA_CRC_FAILED = 8
        case RASTER_METADATA_CRC_FAILED = 16
        case RADIO_APPLICATION_METADATA_CRC_FAILED = 32
        case RADIO_BOOTLOADER_METADATA_CRC_FAILED = 64
        case RADIO_STACK_METADATA_CRC_FAILED = 128
        case ARM_VERSION_FAILED = 256
        case MSP_VERSION_FAILED = 512
        case RADIO_PROCESSOR_VERSION_FAILED = 1024
        case ALPHAMASKS_VERSION_FAILED = 2048
        case RASTER_VERSION_FAILED = 4096
        case RADIO_APPLICATION_VERSION_FAILED = 8192
        case RADIO_BOOTLOADER_VERSION_FAILED = 16384
        case RADIO_STACK_VERSION_FAILED = 32768

        public static func fromBitmask(_ bitmask: Int) -> Set<MetadataAndVersionStatus> {
            var items = Set<MetadataAndVersionStatus>()
            for i in MetadataAndVersionStatus.allCases where (bitmask & i.rawValue) != 0 {
                items.insert(i)
            }
            return items
        }
    }

    public var metadataAndVersionStatusSet: Set<MetadataAndVersionStatus> {
        MetadataAndVersionStatus.fromBitmask(metadataAndVersionStatus)
    }

    /// Bits 0-7: component full download failed; bits 8-15: component CRC failed (Tandem schema FullDlAndCrcStatus).
    public enum FullDlAndCrcStatus: Int, CaseIterable {
        case ARM_FULL_DOWNLOAD_FAILED = 1
        case MSP_FULL_DOWNLOAD_FAILED = 2
        case RADIO_PROCESSOR_FULL_DOWNLOAD_FAILED = 4
        case ALPHAMASKS_FULL_DOWNLOAD_FAILED = 8
        case RASTER_FULL_DOWNLOAD_FAILED = 16
        case RADIO_APPLICATION_FULL_DOWNLOAD_FAILED = 32
        case RADIO_BOOTLOADER_FULL_DOWNLOAD_FAILED = 64
        case RADIO_STACK_FULL_DOWNLOAD_FAILED = 128
        case ARM_CRC_FAILED = 256
        case MSP_CRC_FAILED = 512
        case RADIO_PROCESSOR_CRC_FAILED = 1024
        case ALPHAMASKS_CRC_FAILED = 2048
        case RASTER_CRC_FAILED = 4096
        case RADIO_APPLICATION_CRC_FAILED = 8192
        case RADIO_BOOTLOADER_CRC_FAILED = 16384
        case RADIO_STACK_CRC_FAILED = 32768

        public static func fromBitmask(_ bitmask: Int) -> Set<FullDlAndCrcStatus> {
            var items = Set<FullDlAndCrcStatus>()
            for i in FullDlAndCrcStatus.allCases where (bitmask & i.rawValue) != 0 {
                items.insert(i)
            }
            return items
        }
    }

    public var fullDlAndCrcStatusSet: Set<FullDlAndCrcStatus> {
        FullDlAndCrcStatus.fromBitmask(fullDlAndCrcStatus)
    }

    /// Bits 0-7: component file downloaded; bits 8-15: component sideload started (Tandem schema FileDlAndSideloadStatus).
    public enum FileDlAndSideloadStatus: Int, CaseIterable {
        case ARM_FILE_DOWNLOADED = 1
        case MSP_FILE_DOWNLOADED = 2
        case RADIO_PROCESSOR_FILE_DOWNLOADED = 4
        case ALPHAMASKS_FILE_DOWNLOADED = 8
        case RASTER_FILE_DOWNLOADED = 16
        case RADIO_APPLICATION_FILE_DOWNLOADED = 32
        case RADIO_BOOTLOADER_FILE_DOWNLOADED = 64
        case RADIO_STACK_FILE_DOWNLOADED = 128
        case ARM_SIDELOAD_STARTED = 256
        case MSP_SIDELOAD_STARTED = 512
        case RADIO_PROCESSOR_SIDELOAD_STARTED = 1024
        case ALPHAMASKS_SIDELOAD_STARTED = 2048
        case RASTER_SIDELOAD_STARTED = 4096
        case RADIO_APPLICATION_SIDELOAD_STARTED = 8192
        case RADIO_BOOTLOADER_SIDELOAD_STARTED = 16384
        case RADIO_STACK_SIDELOAD_STARTED = 32768

        public static func fromBitmask(_ bitmask: Int) -> Set<FileDlAndSideloadStatus> {
            var items = Set<FileDlAndSideloadStatus>()
            for i in FileDlAndSideloadStatus.allCases where (bitmask & i.rawValue) != 0 {
                items.insert(i)
            }
            return items
        }
    }

    public var fileDlAndSideloadStatusSet: Set<FileDlAndSideloadStatus> {
        FileDlAndSideloadStatus.fromBitmask(fileDlAndSideloadStatus)
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
