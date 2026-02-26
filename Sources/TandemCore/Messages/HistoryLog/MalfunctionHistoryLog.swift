import Foundation

public class MalfunctionHistoryLog: HistoryLog {
    public static let typeId = 6

    public let malfId: UInt32
    public let faultLocatorData: UInt32
    public let param1: UInt32
    public let param2: Float

    public required init(cargo: Data) {
        malfId = Bytes.readUint32(cargo, 10)
        faultLocatorData = Bytes.readUint32(cargo, 14)
        param1 = Bytes.readUint32(cargo, 18)
        param2 = Bytes.readFloat(cargo, 22)
        super.init(cargo: cargo)
    }
}
