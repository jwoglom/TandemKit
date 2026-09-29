import Foundation

public class DexcomG7CGMHistoryLog: HistoryLog {
    public static let typeId = 399

    public let glucoseValueStatusRaw: Int
    public let cgmDataTypeRaw: Int
    public let rate: Int
    public let algorithmStateRaw: Int
    public let rssi: Int
    public let currentGlucoseDisplayValue: Int
    public let egvTimestamp: UInt32
    public let egvInfoBitmaskRaw: Int
    public let interval: Int
    /// Byte 25, as on G6; the Mobi G7 fixtures have 0 even for five-minute readings. pumpX2#76.
    public let egvCount: Int

    public required init(cargo: Data) {
        glucoseValueStatusRaw = Bytes.readShort(cargo, 10)
        cgmDataTypeRaw = Int(cargo[12])
        rate = Int(Int8(bitPattern: cargo[13]))
        algorithmStateRaw = Int(cargo[14])
        rssi = Int(Int8(bitPattern: cargo[15]))
        currentGlucoseDisplayValue = Bytes.readShort(cargo, 16)
        egvTimestamp = Bytes.readUint32(cargo, 18)
        egvInfoBitmaskRaw = Bytes.readShort(cargo, 22)
        interval = Int(cargo[24])
        egvCount = Int(cargo[25])
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
        egvTimestamp: UInt32,
        egvInfoBitmask: Int,
        interval: Int,
        egvCount: Int = 0
    ) {
        let payload = DexcomG7CGMHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            glucoseValueStatus: glucoseValueStatus,
            cgmDataType: cgmDataType,
            rate: rate,
            algorithmState: algorithmState,
            rssi: rssi,
            currentGlucoseDisplayValue: currentGlucoseDisplayValue,
            egvTimestamp: egvTimestamp,
            egvInfoBitmask: egvInfoBitmask,
            interval: interval,
            egvCount: egvCount
        )
        self.glucoseValueStatusRaw = glucoseValueStatus
        self.cgmDataTypeRaw = cgmDataType
        self.rate = rate
        self.algorithmStateRaw = algorithmState
        self.rssi = rssi
        self.currentGlucoseDisplayValue = currentGlucoseDisplayValue
        self.egvTimestamp = egvTimestamp
        self.egvInfoBitmaskRaw = egvInfoBitmask
        self.interval = interval
        self.egvCount = egvCount
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
        egvTimestamp: UInt32,
        egvInfoBitmask: Int,
        interval: Int,
        egvCount: Int = 0
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId, 1),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(glucoseValueStatus),
                Data([UInt8(cgmDataType & 0xFF)]),
                Data([UInt8(rate & 0xFF)]),
                Data([UInt8(algorithmState & 0xFF)]),
                Data([UInt8(rssi & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(currentGlucoseDisplayValue),
                Bytes.toUint32(egvTimestamp),
                Bytes.firstTwoBytesLittleEndian(egvInfoBitmask),
                Data([UInt8(interval & 0xFF)]),
                Data([UInt8(egvCount & 0xFF)])
            )
        )
    }

    /// Mirrors pumpX2's `DexcomG7CGMHistoryLog.AlgorithmState`.
    public enum AlgorithmState: Int {
        case WARMUP = 2
        case DEFAULT_ELECTRONICS_WAKEUP = 30
        case DETECTING_DEPLOYMENT = 31
        case REPORTABLE_PERIOD_VALID_EGV = 32
        case REPORTABLE_PERIOD_INVALID_EGV = 33
        case STOPPED_END_OF_SESSION = 34
        case STOPPED_ALG_DETECTED_FAILURE = 35
        case STOPPED_MANUAL_STOP = 36
        case STOPPED_TX_FAILURE = 37
        case STOPPED_SIV_FAILURE = 38
        case STOPPED_ENNVIRONMENTAL_CONDITIONS = 39

        public static func fromId(_ id: Int) -> AlgorithmState? {
            AlgorithmState(rawValue: id)
        }
    }

    public var algorithmState: AlgorithmState? {
        AlgorithmState.fromId(algorithmStateRaw)
    }

    /// Mirrors pumpX2's `DexcomG7CGMHistoryLog.GlucoseValueStatus`. Note the case names differ
    /// from `DexcomG6CGMHistoryLog.GlucoseValueStatus` even though the underlying ids match.
    public enum GlucoseValueStatus: Int {
        case NORMAL = 0
        case HIGH = 1
        case LOW = 2
        case DO_NOT_SHOW = 6

        public static func fromId(_ id: Int) -> GlucoseValueStatus? {
            GlucoseValueStatus(rawValue: id)
        }
    }

    public var glucoseValueStatus: GlucoseValueStatus? {
        GlucoseValueStatus.fromId(glucoseValueStatusRaw)
    }

    public var cgmDataType: Set<DexcomG6CGMHistoryLog.CgmDataType> {
        DexcomG6CGMHistoryLog.CgmDataType.fromId(cgmDataTypeRaw)
    }

    public var egvInfo: Set<DexcomG6CGMHistoryLog.EgvInfo> {
        DexcomG6CGMHistoryLog.EgvInfo.fromId(egvInfoBitmaskRaw)
    }

    /// Bits 11-13 of `egvInfoBitmaskRaw`: 3 (G7) in every captured record. pumpX2#76.
    public var egvSensorType: CGMStatusV2Response.CGMSensorType {
        DexcomG6CGMHistoryLog.egvSensorType(egvInfoBitmaskRaw)
    }

    public var description: String {
        "DexcomG7CGMHistoryLog(cargo=\(cargo.hexadecimalString), glucoseValueStatusRaw=\(glucoseValueStatusRaw), cgmDataTypeRaw=\(cgmDataTypeRaw), rate=\(rate), algorithmStateRaw=\(algorithmStateRaw), rssi=\(rssi), currentGlucoseDisplayValue=\(currentGlucoseDisplayValue), egvTimestamp=\(egvTimestamp), egvInfoBitmaskRaw=\(egvInfoBitmaskRaw), interval=\(interval), egvCount=\(egvCount))"
    }
}
