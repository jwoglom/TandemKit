import Foundation

public class ArmInitHistoryLog: HistoryLog {
    public static let typeId = 99

    public let version: UInt32
    public let configABits: UInt32
    public let configBBits: UInt32
    public let numLogEntries: UInt32

    public required init(cargo: Data) {
        version = Bytes.readUint32(cargo, 10)
        configABits = Bytes.readUint32(cargo, 14)
        configBBits = Bytes.readUint32(cargo, 18)
        numLogEntries = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }
}
