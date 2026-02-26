import Foundation

public class CgmAlertClearedDexHistoryLog: HistoryLog {
    public static let typeId = 370

    public let alertId: UInt32

    public required init(cargo: Data) {
        alertId = Bytes.readUint32(cargo, 10)
        super.init(cargo: cargo)
    }
}
