import Foundation

/// History log entry containing Dexcom G6 CGM data (GXB variant).
public class DexcomG6CGMHistoryLog: HistoryLog {
    public static let typeId = 256

    public enum GlucoseValueStatus: Int {
        case normal = 0
        case high = 1
        case low = 2
    }

    public enum CgmDataType: Int, CaseIterable {
        case fiveMinuteReading = 1
        case backfill = 2
        case immediateMatchValue = 4
        case calibration = 8
        case none = 16

        public static func fromMask(_ mask: Int) -> Set<CgmDataType> {
            Set(CgmDataType.allCases.filter { (mask & $0.rawValue) != 0 })
        }
    }

    public enum EgvInfo: Int, CaseIterable {
        case fiveMinuteReading = 1
        case backfill = 2
        case immediateMatchValue = 4
        case calibration = 8
        case noEgv = 16
        case validTimestamp = 32
        case validEgvRange = 64
        case validAlgState = 128
        case egvProcessed = 256

        public static func fromMask(_ mask: Int) -> Set<EgvInfo> {
            Set(EgvInfo.allCases.filter { (mask & $0.rawValue) != 0 })
        }
    }

    public let glucoseValueStatusRaw: Int
    public let glucoseValueStatus: GlucoseValueStatus?
    public let cgmDataTypeRaw: Int
    public let cgmDataTypes: Set<CgmDataType>
    public let rate: Int
    public let algorithmState: Int
    public let rssi: Int
    public let currentGlucoseDisplayValue: Int
    public let timeStampSeconds: UInt32
    public let egvInfoBitmaskRaw: Int
    public let egvInfo: Set<EgvInfo>
    public let interval: Int

    public required init(cargo: Data) {
        glucoseValueStatusRaw = Int(Bytes.readShort(cargo, 10))
        glucoseValueStatus = GlucoseValueStatus(rawValue: glucoseValueStatusRaw)
        cgmDataTypeRaw = Int(cargo[12])
        cgmDataTypes = CgmDataType.fromMask(cgmDataTypeRaw)
        rate = Int(cargo[13])
        algorithmState = Int(cargo[14])
        rssi = Int(cargo[15])
        currentGlucoseDisplayValue = Bytes.readShort(cargo, 16)
        timeStampSeconds = Bytes.readUint32(cargo, 18)
        egvInfoBitmaskRaw = Bytes.readShort(cargo, 22)
        egvInfo = EgvInfo.fromMask(egvInfoBitmaskRaw)
        interval = Int(cargo[24])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        glucoseValueStatusRaw: Int,
        cgmDataTypeRaw: Int,
        rate: Int,
        algorithmState: Int,
        rssi: Int,
        currentGlucoseDisplayValue: Int,
        timeStampSeconds: UInt32,
        egvInfoBitmaskRaw: Int,
        interval: Int
    ) {
        let payload = DexcomG6CGMHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            glucoseValueStatusRaw: glucoseValueStatusRaw,
            cgmDataTypeRaw: cgmDataTypeRaw,
            rate: rate,
            algorithmState: algorithmState,
            rssi: rssi,
            currentGlucoseDisplayValue: currentGlucoseDisplayValue,
            timeStampSeconds: timeStampSeconds,
            egvInfoBitmaskRaw: egvInfoBitmaskRaw,
            interval: interval
        )
        self.glucoseValueStatusRaw = glucoseValueStatusRaw
        self.glucoseValueStatus = GlucoseValueStatus(rawValue: glucoseValueStatusRaw)
        self.cgmDataTypeRaw = cgmDataTypeRaw
        self.cgmDataTypes = CgmDataType.fromMask(cgmDataTypeRaw)
        self.rate = rate
        self.algorithmState = algorithmState
        self.rssi = rssi
        self.currentGlucoseDisplayValue = currentGlucoseDisplayValue
        self.timeStampSeconds = timeStampSeconds
        self.egvInfoBitmaskRaw = egvInfoBitmaskRaw
        self.egvInfo = EgvInfo.fromMask(egvInfoBitmaskRaw)
        self.interval = interval
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        glucoseValueStatusRaw: Int,
        cgmDataTypeRaw: Int,
        rate: Int,
        algorithmState: Int,
        rssi: Int,
        currentGlucoseDisplayValue: Int,
        timeStampSeconds: UInt32,
        egvInfoBitmaskRaw: Int,
        interval: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), UInt8((typeId >> 8) & 0xFF)]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(glucoseValueStatusRaw),
                Data([UInt8(cgmDataTypeRaw & 0xFF)]),
                Data([UInt8(rate & 0xFF)]),
                Data([UInt8(algorithmState & 0xFF)]),
                Data([UInt8(rssi & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(currentGlucoseDisplayValue),
                Bytes.toUint32(timeStampSeconds),
                Bytes.firstTwoBytesLittleEndian(egvInfoBitmaskRaw),
                Data([UInt8(interval & 0xFF)]),
                Data([1])
            )
        )
    }
}

public extension DexcomG6CGMHistoryLog {
    var description: String {
        "DexcomG6CGMHistoryLog(cargo=\(cargo.hexadecimalString), glucoseValueStatusRaw=\(glucoseValueStatusRaw), glucoseValueStatus=\(String(describing: glucoseValueStatus)), cgmDataTypeRaw=\(cgmDataTypeRaw), cgmDataTypes=\(cgmDataTypes), rate=\(rate), algorithmState=\(algorithmState), rssi=\(rssi), currentGlucoseDisplayValue=\(currentGlucoseDisplayValue), timeStampSeconds=\(timeStampSeconds), egvInfoBitmaskRaw=\(egvInfoBitmaskRaw), egvInfo=\(egvInfo), interval=\(interval))"
    }
}
