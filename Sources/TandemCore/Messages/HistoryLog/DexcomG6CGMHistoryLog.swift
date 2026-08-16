import Foundation

public class DexcomG6CGMHistoryLog: HistoryLog {
    public static let typeId = 256

    public let glucoseValueStatus: Int
    public let cgmDataType: Int
    public let rate: Int
    public let algorithmState: Int
    public let rssi: Int
    public let currentGlucoseDisplayValue: Int
    public let timeStampSeconds: UInt32
    public let egvInfoBitmask: Int
    public let interval: Int

    public required init(cargo: Data) {
        glucoseValueStatus = Bytes.readShort(cargo, 10)
        cgmDataType = Int(cargo[12])
        rate = Int(cargo[13])
        algorithmState = Int(cargo[14])
        rssi = Int(cargo[15])
        currentGlucoseDisplayValue = Bytes.readShort(cargo, 16)
        timeStampSeconds = Bytes.readUint32(cargo, 18)
        egvInfoBitmask = Bytes.readShort(cargo, 22)
        interval = Int(cargo[24])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        glucoseValueStatus: Int,
        cgmDataType: Int,
        rate: Int,
        algorithmState: Int,
        rssi: Int,
        currentGlucoseDisplayValue: Int,
        timeStampSeconds: UInt32,
        egvInfoBitmask: Int,
        interval: Int
    ) {
        let payload = DexcomG6CGMHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            glucoseValueStatus: glucoseValueStatus,
            cgmDataType: cgmDataType,
            rate: rate,
            algorithmState: algorithmState,
            rssi: rssi,
            currentGlucoseDisplayValue: currentGlucoseDisplayValue,
            timeStampSeconds: timeStampSeconds,
            egvInfoBitmask: egvInfoBitmask,
            interval: interval
        )
        self.glucoseValueStatus = glucoseValueStatus
        self.cgmDataType = cgmDataType
        self.rate = rate
        self.algorithmState = algorithmState
        self.rssi = rssi
        self.currentGlucoseDisplayValue = currentGlucoseDisplayValue
        self.timeStampSeconds = timeStampSeconds
        self.egvInfoBitmask = egvInfoBitmask
        self.interval = interval
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        glucoseValueStatus: Int,
        cgmDataType: Int,
        rate: Int,
        algorithmState: Int,
        rssi: Int,
        currentGlucoseDisplayValue: Int,
        timeStampSeconds: UInt32,
        egvInfoBitmask: Int,
        interval: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(glucoseValueStatus),
                Data([UInt8(cgmDataType & 0xFF)]),
                Data([UInt8(rate & 0xFF)]),
                Data([UInt8(algorithmState & 0xFF)]),
                Data([UInt8(rssi & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(currentGlucoseDisplayValue),
                Bytes.toUint32(timeStampSeconds),
                Bytes.firstTwoBytesLittleEndian(egvInfoBitmask),
                Data([UInt8(interval & 0xFF)]),
                Data([1]) // trailing param as in Java implementation
            )
        )
    }

    public var glucoseValueStatusEnum: GlucoseValueStatus? {
        GlucoseValueStatus.fromId(glucoseValueStatus)
    }

    public enum GlucoseValueStatus: Int {
        case PRECISE_VALUE = 0
        case SPECIAL_HIGH = 1
        case SPECIAL_LOW = 2
        case DO_NOT_SHOW = 6

        public static func fromId(_ id: Int) -> GlucoseValueStatus? {
            GlucoseValueStatus(rawValue: id)
        }
    }

    public var cgmDataTypes: Set<CgmDataType> {
        CgmDataType.fromId(cgmDataType)
    }

    public enum CgmDataType: Int, CaseIterable {
        case FIVE_MINUTE_READING = 1
        case BACKFILL = 2
        case IMMEDIATE_MATCH_VALUE = 4
        case CALIBRATION = 8
        case NONE = 16

        public static func fromId(_ mask: Int) -> Set<CgmDataType> {
            var items = Set<CgmDataType>()
            for i in CgmDataType.allCases {
                if (mask & i.rawValue) != 0 {
                    items.insert(i)
                }
            }
            return items
        }
    }

    public var egvInfo: Set<EgvInfo> {
        EgvInfo.fromId(egvInfoBitmask)
    }

    public enum EgvInfo: Int, CaseIterable {
        case FIVE_MINUTE_READING = 1
        case BACKFILL = 2
        case IMMEDIATE_MATCH_VALUE = 4
        case CALIBRATION = 8
        case NO_EGV = 16
        case VALID_TIMESTAMP = 32
        case VALID_EGV_RANGE = 64
        case VALID_ALG_STATE = 128
        case EGV_PROCESSED = 256

        public static func fromId(_ mask: Int) -> Set<EgvInfo> {
            var items = Set<EgvInfo>()
            for i in EgvInfo.allCases {
                if (mask & i.rawValue) != 0 {
                    items.insert(i)
                }
            }
            return items
        }
    }
}
