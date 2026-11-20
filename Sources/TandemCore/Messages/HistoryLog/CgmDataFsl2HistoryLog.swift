import Foundation

/// FreeStyle Libre 2 CGM data sample.
///
/// The layout differs from the Dexcom records (`DexcomG6CGMHistoryLog`, `DexcomG7CGMHistoryLog`):
/// the glucose value status and CGM data type are single bytes, the rate of change is a signed
/// 16-bit value, and there is no transmitter timestamp. Field layout per the Tandem Source event schema:
///
///     0  uint8   glucoseValueStatus
///     1  uint8   cgmDataType (bitmask)
///     2  int16   rate (mg/dL/min)
///     4  uint8   algorithmState
///     5  int8    rssi (dBm)
///     6  uint16  currentGlucoseDisplayValue (mg/dL)
///     8  uint32  egvTimestamp (seconds)
///    12  uint16  egvInfoBitmask
///    14  uint8   interval
///    15  uint8   reserved
///
/// Mirrors pumpX2's `CgmDataFsl2HistoryLog`.
public class CgmDataFsl2HistoryLog: HistoryLog {
    public static let typeId = 372

    public let glucoseValueStatusRaw: Int
    public let cgmDataTypeRaw: Int
    /// Signed rate of change, in mg/dL per minute.
    public let rate: Int
    public let algorithmStateRaw: Int
    /// Signed RSSI, in dBm.
    public let rssi: Int
    /// Glucose value, in mg/dL.
    public let currentGlucoseDisplayValue: Int
    public let egvTimestamp: UInt32
    public let egvInfoBitmaskRaw: Int
    public let interval: Int

    public required init(cargo: Data) {
        glucoseValueStatusRaw = Int(cargo[cargo.startIndex + 10])
        cgmDataTypeRaw = Int(cargo[cargo.startIndex + 11])
        rate = Int(Int16(bitPattern: UInt16(truncatingIfNeeded: Bytes.readShort(cargo, 12))))
        algorithmStateRaw = Int(cargo[cargo.startIndex + 14])
        rssi = Int(Int8(bitPattern: cargo[cargo.startIndex + 15]))
        currentGlucoseDisplayValue = Bytes.readShort(cargo, 16)
        egvTimestamp = Bytes.readUint32(cargo, 18)
        egvInfoBitmaskRaw = Bytes.readShort(cargo, 22)
        interval = Int(cargo[cargo.startIndex + 24])
        super.init(cargo: cargo)
    }

    public convenience init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        self.init(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, glucoseValueStatus: 0, cgmDataType: 0, rate: 0, algorithmState: 0, rssi: 0, currentGlucoseDisplayValue: 0, egvTimestamp: 0, egvInfoBitmask: 0, interval: 0)
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
        interval: Int
    ) {
        let payload = CgmDataFsl2HistoryLog.buildCargo(
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
            interval: interval
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
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, glucoseValueStatus: 0, cgmDataType: 0, rate: 0, algorithmState: 0, rssi: 0, currentGlucoseDisplayValue: 0, egvTimestamp: 0, egvInfoBitmask: 0, interval: 0)
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
        interval: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(glucoseValueStatus & 0xFF)]),
                Data([UInt8(cgmDataType & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(rate & 0xFFFF),
                Data([UInt8(algorithmState & 0xFF)]),
                Data([UInt8(rssi & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(currentGlucoseDisplayValue),
                Bytes.toUint32(egvTimestamp),
                Bytes.firstTwoBytesLittleEndian(egvInfoBitmask),
                Data([UInt8(interval & 0xFF)]),
                Data([0])
            )
        )
    }

    public enum GlucoseValueStatus: Int {
        case PRECISE_VALUE = 0
        case SPECIAL_HIGH = 1
        case SPECIAL_LOW = 2

        public static func fromId(_ id: Int) -> GlucoseValueStatus? {
            GlucoseValueStatus(rawValue: id)
        }
    }

    /// Bitmask describing the type of reading. Unlike the Dexcom records, Libre readings
    /// can also be one-minute readings (OMR).
    public enum CgmDataType: Int, CaseIterable {
        case FIVE_MINUTE_READING = 1
        case BACKFILL = 2
        case NONE = 16
        case ONE_MINUTE_READING = 32

        public static func fromId(_ mask: Int) -> Set<CgmDataType> {
            var items = Set<CgmDataType>()
            for i in CgmDataType.allCases where (mask & i.rawValue) != 0 {
                items.insert(i)
            }
            return items
        }
    }

    public enum AlgorithmState: Int {
        case WARMUP = 2
        case OK = 100
        case RF_ERROR = 101
        case SENSOR_SIGNAL_LOW = 102
        case TEMP_HIGH = 103
        case TEMP_LOW = 104
        case INVALID_DATA = 105
        case OTHER_DQ = 106
        case EGV_UNUSABLE = 107

        public static func fromId(_ id: Int) -> AlgorithmState? {
            AlgorithmState(rawValue: id)
        }
    }

    /// EGV info bitmask. Bits 11-13 encode the sensor type (2 = Libre 2, 4 = Libre 3), see `sensorType`.
    public enum EgvInfo: Int, CaseIterable {
        case FIVE_MINUTE_READING = 1
        case BACKFILL = 2
        case NO_EGV = 16
        case VALID_TIMESTAMP = 32
        case VALID_EGV_RANGE = 64
        case VALID_ALG_STATE = 128
        case EGV_PROCESSED = 256
        case ONE_MINUTE_READING = 512

        public static func fromId(_ mask: Int) -> Set<EgvInfo> {
            var items = Set<EgvInfo>()
            for i in EgvInfo.allCases where (mask & i.rawValue) != 0 {
                items.insert(i)
            }
            return items
        }
    }

    public var glucoseValueStatus: CgmDataFsl2HistoryLog.GlucoseValueStatus? {
        CgmDataFsl2HistoryLog.GlucoseValueStatus.fromId(glucoseValueStatusRaw)
    }

    public var cgmDataType: Set<CgmDataFsl2HistoryLog.CgmDataType> {
        CgmDataFsl2HistoryLog.CgmDataType.fromId(cgmDataTypeRaw)
    }

    public var algorithmState: CgmDataFsl2HistoryLog.AlgorithmState? {
        CgmDataFsl2HistoryLog.AlgorithmState.fromId(algorithmStateRaw)
    }

    public var egvInfo: Set<CgmDataFsl2HistoryLog.EgvInfo> {
        CgmDataFsl2HistoryLog.EgvInfo.fromId(egvInfoBitmaskRaw)
    }

    /// Sensor type encoded in bits 11-13 of the EGV info bitmask (2 = Libre 2, 4 = Libre 3).
    public var sensorType: Int {
        (egvInfoBitmaskRaw >> 11) & 0x7
    }

    @available(*, deprecated, renamed: "glucoseValueStatusRaw")
    public var status: Int { glucoseValueStatusRaw }
    @available(*, deprecated, renamed: "cgmDataTypeRaw")
    public var type: Int { cgmDataTypeRaw }
    @available(*, deprecated, renamed: "currentGlucoseDisplayValue")
    public var value: Int { currentGlucoseDisplayValue }
    @available(*, deprecated, renamed: "egvTimestamp")
    public var timestamp: UInt32 { egvTimestamp }

    override public var description: String {
        "CgmDataFsl2HistoryLog(cargo=\(cargo.hexadecimalString), glucoseValueStatusRaw=\(glucoseValueStatusRaw), cgmDataTypeRaw=\(cgmDataTypeRaw), rate=\(rate), algorithmStateRaw=\(algorithmStateRaw), rssi=\(rssi), currentGlucoseDisplayValue=\(currentGlucoseDisplayValue), egvTimestamp=\(egvTimestamp), egvInfoBitmaskRaw=\(egvInfoBitmaskRaw), interval=\(interval))"
    }
}
