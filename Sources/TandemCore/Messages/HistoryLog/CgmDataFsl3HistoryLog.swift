import Foundation

/// FreeStyle Libre 3 CGM data sample. Same layout as `CgmDataFsl2HistoryLog`, whose enums it reuses.
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
/// Mirrors pumpX2's `CgmDataFsl3HistoryLog`.
public class CgmDataFsl3HistoryLog: HistoryLog {
    public static let typeId = 480

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
        let payload = CgmDataFsl3HistoryLog.buildCargo(
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
        "CgmDataFsl3HistoryLog(cargo=\(cargo.hexadecimalString), glucoseValueStatusRaw=\(glucoseValueStatusRaw), cgmDataTypeRaw=\(cgmDataTypeRaw), rate=\(rate), algorithmStateRaw=\(algorithmStateRaw), rssi=\(rssi), currentGlucoseDisplayValue=\(currentGlucoseDisplayValue), egvTimestamp=\(egvTimestamp), egvInfoBitmaskRaw=\(egvInfoBitmaskRaw), interval=\(interval))"
    }
}
