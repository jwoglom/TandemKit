import Foundation

public class CgmAlertActivatedFsl2HistoryLog: HistoryLog {
    public static let typeId = 460

    public let alertId: UInt32

    public required init(cargo: Data) {
        alertId = Bytes.readUint32(cargo, 10)
        super.init(cargo: cargo)
    }
}
