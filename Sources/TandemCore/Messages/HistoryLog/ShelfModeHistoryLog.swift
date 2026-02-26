import Foundation

public class ShelfModeHistoryLog: HistoryLog {
    public static let typeId = 53

    public let msecSinceReset: UInt32
    public let lipoIbc: Int
    public let lipoAbc: Int
    public let lipoCurrent: Int
    public let lipoRemCap: UInt32
    public let lipoMv: UInt32

    public required init(cargo: Data) {
        msecSinceReset = Bytes.readUint32(cargo, 10)
        lipoIbc = Int(cargo[14])
        lipoAbc = Int(cargo[15])
        lipoCurrent = Bytes.readShort(cargo, 16)
        lipoRemCap = Bytes.readUint32(cargo, 18)
        lipoMv = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }
}
