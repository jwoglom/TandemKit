import Foundation

/// The Mobi's running cartridge estimate, written about every 4 U delivered and during fills.
/// Provisional name; see https://github.com/jwoglom/pumpX2/issues/148.
public class ReservoirEstimateHistoryLog: HistoryLog {
    public static let typeId = 231

    /// `insulinDelivered + insulinRemaining` equalled this (about 203.94 U) in every observed record.
    public static let observedStartEstimate = Float(bitPattern: 0x434B_EFF2)

    /// Units moved out of the cartridge since it was inserted, priming included.
    public let insulinDelivered: Float
    /// Units left by the pump's estimate: `observedStartEstimate - insulinDelivered`, not a separate measurement.
    public let insulinRemaining: Float
    /// Whole units as reported: nearest 5 U at or above 40 U, rounded down below 40 U, 0 during a fill.
    public let displayedInsulinRemaining: Int
    /// Drive position, about 1073.5 counts per unit; near 2^19 at cartridge insertion.
    public let driveCounter: UInt32

    public required init(cargo: Data) {
        insulinDelivered = Bytes.readFloat(cargo, 10)
        insulinRemaining = Bytes.readFloat(cargo, 14)
        displayedInsulinRemaining = Int(cargo[cargo.startIndex + 18])
        driveCounter = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        insulinDelivered: Float,
        insulinRemaining: Float,
        displayedInsulinRemaining: Int,
        driveCounter: UInt32
    ) {
        let payload = ReservoirEstimateHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            insulinDelivered: insulinDelivered,
            insulinRemaining: insulinRemaining,
            displayedInsulinRemaining: displayedInsulinRemaining,
            driveCounter: driveCounter
        )
        self.insulinDelivered = insulinDelivered
        self.insulinRemaining = insulinRemaining
        self.displayedInsulinRemaining = displayedInsulinRemaining
        self.driveCounter = driveCounter
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        insulinDelivered: Float,
        insulinRemaining: Float,
        displayedInsulinRemaining: Int,
        driveCounter: UInt32
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toFloat(insulinDelivered),
                Bytes.toFloat(insulinRemaining),
                Bytes.firstByteLittleEndian(displayedInsulinRemaining),
                Data(count: 3),
                Bytes.toUint32(driveCounter)
            )
        )
    }

    override public var description: String {
        "ReservoirEstimateHistoryLog(cargo=\(cargo.hexadecimalString), insulinDelivered=\(insulinDelivered), insulinRemaining=\(insulinRemaining), displayedInsulinRemaining=\(displayedInsulinRemaining), driveCounter=\(driveCounter))"
    }
}
