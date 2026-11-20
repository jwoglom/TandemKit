import Foundation

/// Two-hourly Mobi counters (jwoglom/pumpX2#151). Provisional name; `unknown*` fields are unidentified.
/// `controlRequestCount` counts CONTROL requests since the previous burst and always equals unknown18 + unknown22.
public class ControlRequestCountersHistoryLog: HistoryLog {
    public static let typeId = 492

    public let controlRequestCount: UInt32
    public let unknown14: UInt32
    public let unknown18: UInt32
    public let unknown22: UInt32

    public required init(cargo: Data) {
        controlRequestCount = Bytes.readUint32(cargo, 10)
        unknown14 = Bytes.readUint32(cargo, 14)
        unknown18 = Bytes.readUint32(cargo, 18)
        unknown22 = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, controlRequestCount: UInt32, unknown14: UInt32, unknown18: UInt32, unknown22: UInt32) {
        let payload = ControlRequestCountersHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            controlRequestCount: controlRequestCount,
            unknown14: unknown14,
            unknown18: unknown18,
            unknown22: unknown22
        )
        self.controlRequestCount = controlRequestCount
        self.unknown14 = unknown14
        self.unknown18 = unknown18
        self.unknown22 = unknown22
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, controlRequestCount: UInt32, unknown14: UInt32, unknown18: UInt32, unknown22: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(controlRequestCount),
                Bytes.toUint32(unknown14),
                Bytes.toUint32(unknown18),
                Bytes.toUint32(unknown22)
            )
        )
    }

    override public var description: String {
        "ControlRequestCountersHistoryLog(cargo=\(cargo.hexadecimalString), controlRequestCount=\(controlRequestCount), unknown14=\(unknown14), unknown18=\(unknown18), unknown22=\(unknown22))"
    }
}
