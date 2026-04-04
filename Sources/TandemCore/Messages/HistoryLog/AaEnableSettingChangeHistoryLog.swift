import Foundation

public class AaEnableSettingChangeHistoryLog: HistoryLog {
    public static let typeId = 244

    public let enabled: Bool

    public required init(cargo: Data) {
        enabled = cargo[10] != 0
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, enabled: Bool) {
        let payload = AaEnableSettingChangeHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, enabled: enabled)
        self.enabled = enabled
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, enabled: Bool) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([enabled ? 1 : 0])
            )
        )
    }

    public var description: String {
        "AaEnableSettingChangeHistoryLog(cargo=\(cargo.hexadecimalString), enabled=\(enabled))"
    }
}
