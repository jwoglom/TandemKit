import Foundation

/// History log entry containing Dexcom G7 CGM data.
public class DexcomG7CGMHistoryLog: HistoryLog {
    public static let typeId = 399

    public enum AlgorithmState: Int, CaseIterable {
        case warmup = 2
        case defaultElectronicsWakeup = 30
        case detectingDeployment = 31
        case reportablePeriodValidEgv = 32
        case reportablePeriodInvalidEgv = 33
        case stoppedEndOfSession = 34
        case stoppedAlgDetectedFailure = 35
        case stoppedManualStop = 36
        case stoppedTxFailure = 37
        case stoppedSivFailure = 38
        case stoppedEnvironmentalConditions = 39
    }

    public enum GlucoseValueStatus: Int {
        case normal = 0
        case high = 1
        case low = 2
        case doNotShow = 6
    }

    public let glucoseValueStatusRaw: Int
    public let glucoseValueStatus: GlucoseValueStatus?
    public let cgmDataTypeRaw: Int
    public let cgmDataType: Set<DexcomG6CGMHistoryLog.CgmDataType>
    public let rate: Int
    public let algorithmStateRaw: Int
    public let algorithmState: AlgorithmState?
    public let rssi: Int
    public let currentGlucoseDisplayValue: Int
    public let egvTimestamp: UInt32
    public let egvInfoBitmaskRaw: Int
    public let egvInfo: Set<DexcomG6CGMHistoryLog.EgvInfo>
    public let interval: Int

    public required init(cargo: Data) {
        glucoseValueStatusRaw = Int(Bytes.readShort(cargo, 10))
        glucoseValueStatus = GlucoseValueStatus(rawValue: glucoseValueStatusRaw)
        cgmDataTypeRaw = Int(cargo[12])
        cgmDataType = DexcomG6CGMHistoryLog.CgmDataType.fromMask(cgmDataTypeRaw)
        rate = Int(cargo[13])
        algorithmStateRaw = Int(cargo[14])
        algorithmState = AlgorithmState(rawValue: algorithmStateRaw)
        rssi = Int(cargo[15])
        currentGlucoseDisplayValue = Bytes.readShort(cargo, 16)
        egvTimestamp = Bytes.readUint32(cargo, 18)
        egvInfoBitmaskRaw = Bytes.readShort(cargo, 22)
        egvInfo = DexcomG6CGMHistoryLog.EgvInfo.fromMask(egvInfoBitmaskRaw)
        interval = Int(cargo[24])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        glucoseValueStatusRaw: Int,
        cgmDataTypeRaw: Int,
        rate: Int,
        algorithmStateRaw: Int,
        rssi: Int,
        currentGlucoseDisplayValue: Int,
        egvTimestamp: UInt32,
        egvInfoBitmaskRaw: Int,
        interval: Int
    ) {
        let payload = DexcomG7CGMHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            glucoseValueStatusRaw: glucoseValueStatusRaw,
            cgmDataTypeRaw: cgmDataTypeRaw,
            rate: rate,
            algorithmStateRaw: algorithmStateRaw,
            rssi: rssi,
            currentGlucoseDisplayValue: currentGlucoseDisplayValue,
            egvTimestamp: egvTimestamp,
            egvInfoBitmaskRaw: egvInfoBitmaskRaw,
            interval: interval
        )
        self.glucoseValueStatusRaw = glucoseValueStatusRaw
        self.glucoseValueStatus = GlucoseValueStatus(rawValue: glucoseValueStatusRaw)
        self.cgmDataTypeRaw = cgmDataTypeRaw
        self.cgmDataType = DexcomG6CGMHistoryLog.CgmDataType.fromMask(cgmDataTypeRaw)
        self.rate = rate
        self.algorithmStateRaw = algorithmStateRaw
        self.algorithmState = AlgorithmState(rawValue: algorithmStateRaw)
        self.rssi = rssi
        self.currentGlucoseDisplayValue = currentGlucoseDisplayValue
        self.egvTimestamp = egvTimestamp
        self.egvInfoBitmaskRaw = egvInfoBitmaskRaw
        self.egvInfo = DexcomG6CGMHistoryLog.EgvInfo.fromMask(egvInfoBitmaskRaw)
        self.interval = interval
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        glucoseValueStatusRaw: Int,
        cgmDataTypeRaw: Int,
        rate: Int,
        algorithmStateRaw: Int,
        rssi: Int,
        currentGlucoseDisplayValue: Int,
        egvTimestamp: UInt32,
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
                Data([UInt8(algorithmStateRaw & 0xFF)]),
                Data([UInt8(rssi & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(currentGlucoseDisplayValue),
                Bytes.toUint32(egvTimestamp),
                Bytes.firstTwoBytesLittleEndian(egvInfoBitmaskRaw),
                Data([UInt8(interval & 0xFF)])
            )
        )
    }
}

public extension DexcomG7CGMHistoryLog {
    var description: String {
        "DexcomG7CGMHistoryLog(cargo=\(cargo.hexadecimalString), glucoseValueStatusRaw=\(glucoseValueStatusRaw), glucoseValueStatus=\(String(describing: glucoseValueStatus)), cgmDataTypeRaw=\(cgmDataTypeRaw), cgmDataType=\(cgmDataType), rate=\(rate), algorithmStateRaw=\(algorithmStateRaw), algorithmState=\(String(describing: algorithmState)), rssi=\(rssi), currentGlucoseDisplayValue=\(currentGlucoseDisplayValue), egvTimestamp=\(egvTimestamp), egvInfoBitmaskRaw=\(egvInfoBitmaskRaw), egvInfo=\(egvInfo), interval=\(interval))"
    }
}
