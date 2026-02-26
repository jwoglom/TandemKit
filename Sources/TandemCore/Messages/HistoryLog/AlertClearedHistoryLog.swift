import Foundation

public class AlertClearedHistoryLog: HistoryLog {
    public static let typeId = 26

    public let alertId: UInt32
    public let faultLocatorData: UInt32

    public required init(cargo: Data) {
        alertId = Bytes.readUint32(cargo, 10)
        faultLocatorData = Bytes.readUint32(cargo, 14)
        super.init(cargo: cargo)
    }
}
