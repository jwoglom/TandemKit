import Foundation
import LoopKit

public extension DoseEntry {
    static func bolus(
        units: Double,
        deliveredUnits: Double,
        duration: TimeInterval,
        activationType: BolusActivationType,
        insulinType: InsulinType?,
        decisionId: UUID? = nil,
        startDate: Date = Date.now,
        endDate: Date? = nil,
        now: Date = Date.now
    ) -> DoseEntry {
        if let endDate = endDate {
            return DoseEntry(
                type: .bolus,
                startDate: startDate,
                endDate: endDate,
                value: units,
                unit: .units,
                decisionId: decisionId,
                deliveredUnits: deliveredUnits,
                insulinType: insulinType,
                automatic: activationType.isAutomatic,
                isMutable: false
            )
        }

        return DoseEntry(
            type: .bolus,
            startDate: startDate,
            endDate: now.addingTimeInterval(duration),
            value: units,
            unit: .units,
            decisionId: decisionId,
            deliveredUnits: deliveredUnits,
            insulinType: insulinType,
            automatic: activationType.isAutomatic,
            isMutable: true
        )
    }
}
