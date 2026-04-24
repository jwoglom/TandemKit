import Foundation

public class CgmBleCalibrationEvtG7HistoryLog: HistoryLog {
    public static let typeId = 439

    public let isCalibrationAccepted: Bool

    public required init(cargo: Data) {
        isCalibrationAccepted = cargo[10] != 0
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, isCalibrationAccepted: Bool) {
        let payload = CgmBleCalibrationEvtG7HistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            isCalibrationAccepted: isCalibrationAccepted
        )
        self.isCalibrationAccepted = isCalibrationAccepted
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, isCalibrationAccepted: Bool) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), UInt8((typeId >> 8) & 0xFF)]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([isCalibrationAccepted ? 1 : 0])
            )
        )
    }

    public var description: String {
        "CgmBleCalibrationEvtG7HistoryLog(cargo=\(cargo.hexadecimalString), isCalibrationAccepted=\(isCalibrationAccepted))"
    }
}
