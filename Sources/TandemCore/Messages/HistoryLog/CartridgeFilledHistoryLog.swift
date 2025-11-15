import Foundation

public class CartridgeFilledHistoryLog: HistoryLog {
    public static let typeId = 33

    /// A user-facing displayable amount of insulin filled.
    public let insulinDisplay: UInt32
    /// The actual amount of insulin mechanically filled by the pump.
    public let insulinActual: Float

    public required init(cargo: Data) {
        insulinDisplay = Bytes.readUint32(cargo, 10)
        insulinActual = Bytes.readFloat(cargo, 14)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, insulinDisplay: UInt32, insulinActual: Float) {
        let payload = CartridgeFilledHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            insulinDisplay: insulinDisplay,
            insulinActual: insulinActual
        )
        self.insulinDisplay = insulinDisplay
        self.insulinActual = insulinActual
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        insulinDisplay: UInt32,
        insulinActual: Float
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(insulinDisplay),
                Bytes.toFloat(insulinActual)
            )
        )
    }
}
