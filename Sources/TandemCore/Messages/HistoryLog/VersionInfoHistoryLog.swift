import Foundation

public class VersionInfoHistoryLog: HistoryLog {
    public static let typeId = 191

    public let version: UInt32
    public let configABits: UInt32
    public let configBBits: UInt32
    public let armCrc: Int

    public required init(cargo: Data) {
        version = Bytes.readUint32(cargo, 10)
        configABits = Bytes.readUint32(cargo, 14)
        configBBits = Bytes.readUint32(cargo, 18)
        armCrc = Bytes.readShort(cargo, 24)
        super.init(cargo: cargo)
    }
}
