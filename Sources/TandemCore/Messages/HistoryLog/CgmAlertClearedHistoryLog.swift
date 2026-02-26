import Foundation

public class CgmAlertClearedHistoryLog: HistoryLog {
    public static let typeId = 172

    public let alertId: UInt32

    public required init(cargo: Data) {
        alertId = Bytes.readUint32(cargo, 10)
        super.init(cargo: cargo)
    }
}
