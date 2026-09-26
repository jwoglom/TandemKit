import Foundation

/// The pump's PumpFeaturesV2 `controlIqFeatures` bitmask (0 where that index is unsupported), fixed by firmware; written at boot and after each NewDay.
/// Provisional name; see https://github.com/jwoglom/pumpX2/issues/152. Bytes 14-25 have always been zero.
public class ControlIQFeaturesHistoryLog: HistoryLog {
    public static let typeId = 328

    /// 0, 49, 3072 or 896 observed; bits 4, 5, 7 and 10 have no `ControlIqFeatureType` name.
    public let controlIqFeaturesBitmask: UInt32
    public let unknownTail: Data

    public required init(cargo: Data) {
        let start = cargo.startIndex
        controlIqFeaturesBitmask = Bytes.readUint32(cargo, 10)
        unknownTail = Data(cargo[(start + 14) ..< (start + 26)])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        controlIqFeaturesBitmask: UInt32,
        unknownTail: Data = Data(count: 12)
    ) {
        let payload = ControlIQFeaturesHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            controlIqFeaturesBitmask: controlIqFeaturesBitmask,
            unknownTail: unknownTail
        )
        self.controlIqFeaturesBitmask = controlIqFeaturesBitmask
        self.unknownTail = payload.subdata(in: (payload.startIndex + 14) ..< (payload.startIndex + 26))
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        controlIqFeaturesBitmask: UInt32,
        unknownTail: Data = Data(count: 12)
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(controlIqFeaturesBitmask),
                unknownTail.prefix(12)
            )
        )
    }

    public var controlIqFeatures: Set<PumpFeaturesV2Response.ControlIqFeatureType> {
        PumpFeaturesV2Response.ControlIqFeatureType.fromBitmask(controlIqFeaturesBitmask)
    }

    public var description: String {
        "ControlIQFeaturesHistoryLog(cargo=\(cargo.hexadecimalString), controlIqFeaturesBitmask=\(controlIqFeaturesBitmask), unknownTail=\(unknownTail.hexadecimalString))"
    }
}
