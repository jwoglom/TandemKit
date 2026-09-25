import Foundation

/// A press (state 1) or release (state 0) of the pump button. Provisional reading;
/// see https://github.com/jwoglom/pumpX2/issues/148.
public class PumpButtonHistoryLog: HistoryLog {
    public static let typeId = 17

    /// Milliseconds since midnight on the pump's local clock (`timeOfDayMs / 1000 == pumpTimeSec % 86400`).
    public let timeOfDayMs: UInt32
    public let state: Int

    public var isPressed: Bool {
        state == 1
    }

    public required init(cargo: Data) {
        timeOfDayMs = Bytes.readUint32(cargo, 10)
        state = Int(cargo[cargo.startIndex + 14])
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, timeOfDayMs: UInt32, state: Int) {
        let payload = PumpButtonHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            timeOfDayMs: timeOfDayMs,
            state: state
        )
        self.timeOfDayMs = timeOfDayMs
        self.state = state
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, timeOfDayMs: UInt32, state: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(timeOfDayMs),
                Bytes.firstByteLittleEndian(state)
            )
        )
    }

    public var description: String {
        "PumpButtonHistoryLog(cargo=\(cargo.hexadecimalString), timeOfDayMs=\(timeOfDayMs), state=\(state))"
    }
}
