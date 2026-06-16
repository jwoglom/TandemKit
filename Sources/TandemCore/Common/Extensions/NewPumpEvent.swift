import Foundation
import LoopKit

public extension NewPumpEvent {
    static func bolus(dose: DoseEntry, units: Double, date: Date = Date.now) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: dose,
            raw: "\(DoseType.bolus.rawValue) \(units) \(dateFormatter.string(from: date))".data(using: .utf8) ?? Data([]),
            title: String(localized: "Bolus", comment: "Pump Event title for UnfinalizedDose with doseType of .bolus")
        )
    }

    static func tempBasal(dose: DoseEntry, date: Date = Date.now) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: dose,
            raw: "\(DoseType.tempBasal.rawValue) \(dose.programmedUnits) \(dateFormatter.string(from: date))"
                .data(using: .utf8) ?? Data([]),
            title: String(localized: "Temp Basal", comment: "Pump Event title for UnfinalizedDose with doseType of .tempBasal")
        )
    }

    static func basal(dose: DoseEntry, date: Date = Date.now) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: dose,
            raw: "\(DoseType.basal.rawValue) \(dateFormatter.string(from: date))".data(using: .utf8) ?? Data([]),
            title: String(localized: "Basal", comment: "Pump Event title for UnfinalizedDose with doseType of .basal")
        )
    }

    static func resume(dose: DoseEntry, date: Date = Date.now) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: dose,
            raw: "\(DoseType.resume.rawValue) \(dateFormatter.string(from: date))".data(using: .utf8) ?? Data([]),
            title: String(localized: "Resume", comment: "Pump Event title for UnfinalizedDose with doseType of .resume")
        )
    }

    static func suspend(dose: DoseEntry, date: Date = Date.now) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: dose,
            raw: "\(DoseType.suspend.rawValue) \(dateFormatter.string(from: date))".data(using: .utf8) ?? Data([]),
            title: String(localized: "Suspend", comment: "Pump Event title for UnfinalizedDose with doseType of .suspend")
        )
    }

    /// Cannula / infusion-set change, reported as a `.replaceComponent` pump event.
    /// Emitted when the user fills the cannula.
    static func siteChange(date: Date = Date.now) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: nil,
            raw: "siteChange \(dateFormatter.string(from: date))".data(using: .utf8) ?? Data([]),
            title: String(localized: "Site Change", comment: "Pump Event title for a cannula/infusion-set change"),
            type: .replaceComponent(componentType: .infusionSet)
        )
    }

    /// Cartridge / reservoir change, reported as a `.rewind` pump event.
    /// Emitted when the user changes the cartridge.
    static func cartridgeChange(date: Date = Date.now) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: nil,
            raw: "cartridgeChange \(dateFormatter.string(from: date))".data(using: .utf8) ?? Data([]),
            title: String(localized: "Cartridge Change", comment: "Pump Event title for a cartridge/reservoir change"),
            type: .rewind
        )
    }
}
