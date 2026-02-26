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
}
