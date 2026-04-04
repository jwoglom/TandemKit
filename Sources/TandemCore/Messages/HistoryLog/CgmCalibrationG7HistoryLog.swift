import Foundation

public class CgmCalibrationG7HistoryLog: HistoryLog {
    public static let typeId = 438

    public let bg: UInt32

    public required init(cargo: Data) {
        bg = Bytes.readUint32(cargo, 10)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, bg: UInt32) {
        let payload = CgmCalibrationG7HistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, bg: bg)
        self.bg = bg
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, bg: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), UInt8((typeId >> 8) & 0xFF)]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(bg)
            )
        )
    }

    public var description: String {
        "CgmCalibrationG7HistoryLog(cargo=\(cargo.hexadecimalString), bg=\(bg))"
    }
}
