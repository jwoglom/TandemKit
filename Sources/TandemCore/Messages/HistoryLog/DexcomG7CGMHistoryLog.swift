import Foundation

public class DexcomG7CGMHistoryLog: HistoryLog {
    public static let typeId = 399

    public let glucoseValueStatus: Int
    public let cgmDataType: Int
    public let rate: Int
    public let algorithmState: Int
    public let rssi: Int
    public let currentGlucoseDisplayValue: Int
    public let egvTimestamp: UInt32
    public let egvInfoBitmask: Int
    public let interval: Int

    public required init(cargo: Data) {
        glucoseValueStatus = Bytes.readShort(cargo, 10)
        cgmDataType = Int(cargo[12])
        rate = Int(Int8(bitPattern: cargo[13]))
        algorithmState = Int(cargo[14])
        rssi = Int(Int8(bitPattern: cargo[15]))
        currentGlucoseDisplayValue = Bytes.readShort(cargo, 16)
        egvTimestamp = Bytes.readUint32(cargo, 18)
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
        egvTimestamp: UInt32,
        egvInfoBitmask: Int,
        interval: Int
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
            interval: interval
        )
        self.glucoseValueStatus = glucoseValueStatus
        self.cgmDataType = cgmDataType
        self.rate = rate
        self.algorithmState = algorithmState
        self.rssi = rssi
        self.currentGlucoseDisplayValue = currentGlucoseDisplayValue
        self.egvTimestamp = egvTimestamp
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
        egvTimestamp: UInt32,
        egvInfoBitmask: Int,
        interval: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(399 & 0xFF), 0x11]),
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
                Data([UInt8(interval & 0xFF)])
            )
        )
    }

    public var description: String {
        "DexcomG7CGMHistoryLog(cargo=\(cargo.hexadecimalString), glucoseValueStatus=\(glucoseValueStatus), cgmDataType=\(cgmDataType), rate=\(rate), algorithmState=\(algorithmState), rssi=\(rssi), currentGlucoseDisplayValue=\(currentGlucoseDisplayValue), egvTimestamp=\(egvTimestamp), egvInfoBitmask=\(egvInfoBitmask), interval=\(interval))"
    }
}
