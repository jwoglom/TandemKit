import Foundation

/// Two-hourly Mobi counters (jwoglom/pumpX2#151). Provisional name; `unknown*` fields are unidentified.
/// `controlStreamMessageCount` counts CONTROL_STREAM notifications since the previous burst.
public class ControlStreamCountersHistoryLog: HistoryLog {
    public static let typeId = 493

    public let controlStreamMessageCount: UInt32
    public let unknown14: UInt32
    public let unknown18: UInt32
    public let unknown22: UInt32

    public required init(cargo: Data) {
        controlStreamMessageCount = Bytes.readUint32(cargo, 10)
        unknown14 = Bytes.readUint32(cargo, 14)
        unknown18 = Bytes.readUint32(cargo, 18)
        unknown22 = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, controlStreamMessageCount: UInt32, unknown14: UInt32, unknown18: UInt32, unknown22: UInt32) {
        let payload = ControlStreamCountersHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            controlStreamMessageCount: controlStreamMessageCount,
            unknown14: unknown14,
            unknown18: unknown18,
            unknown22: unknown22
        )
        self.controlStreamMessageCount = controlStreamMessageCount
        self.unknown14 = unknown14
        self.unknown18 = unknown18
        self.unknown22 = unknown22
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, controlStreamMessageCount: UInt32, unknown14: UInt32, unknown18: UInt32, unknown22: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(controlStreamMessageCount),
                Bytes.toUint32(unknown14),
                Bytes.toUint32(unknown18),
                Bytes.toUint32(unknown22)
            )
        )
    }

    override public var description: String {
        "ControlStreamCountersHistoryLog(cargo=\(cargo.hexadecimalString), controlStreamMessageCount=\(controlStreamMessageCount), unknown14=\(unknown14), unknown18=\(unknown18), unknown22=\(unknown22))"
    }
}
