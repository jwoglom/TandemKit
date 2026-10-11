import Foundation
import LoopKit

public extension NewPumpEvent {
    /// Keyed on the programmed amount: `raw` is the dose's identity, so finalizing must not
    /// change it (#328).
    static func bolus(dose: DoseEntry, date: Date = Date.now) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: dose,
            raw: "\(DoseType.bolus.rawValue) \(dose.programmedUnits) \(dateFormatter.string(from: date))"
                .data(using: .utf8) ?? Data([]),
            title: String(localized: "Bolus", comment: "Pump Event title for UnfinalizedDose with doseType of .bolus")
        )
    }

    /// `dose` is `temp` as reported now, under `temp`'s identity whatever it ends at.
    static func tempBasal(dose: DoseEntry, of temp: UnfinalizedDose) -> NewPumpEvent {
        NewPumpEvent(
            date: temp.startDate,
            dose: dose,
            raw: temp.tempBasalRaw,
            title: String(localized: "Temp Basal", comment: "Pump Event title for UnfinalizedDose with doseType of .tempBasal")
        )
    }

    static func basal(dose: DoseEntry, date: Date = Date.now) -> NewPumpEvent {
        NewPumpEvent(
            date: date,
            dose: dose,
            raw: deliveryChangeRaw(.basal, at: date),
            title: String(localized: "Basal", comment: "Pump Event title for UnfinalizedDose with doseType of .basal")
        )
    }

    static func resume(dose: DoseEntry, date: Date = Date.now) -> NewPumpEvent {
        NewPumpEvent(
            date: date,
            dose: dose,
            raw: deliveryChangeRaw(.resume, at: date),
            title: String(localized: "Resume", comment: "Pump Event title for UnfinalizedDose with doseType of .resume")
        )
    }

    static func suspend(dose: DoseEntry, date: Date = Date.now) -> NewPumpEvent {
        NewPumpEvent(
            date: date,
            dose: dose,
            raw: deliveryChangeRaw(.suspend, at: date),
            title: String(localized: "Suspend", comment: "Pump Event title for UnfinalizedDose with doseType of .suspend")
        )
    }

    /// To the millisecond: each host keeps one row per `raw`, and two changes of one type can fall
    /// in one second.
    private static func deliveryChangeRaw(_ type: DoseType, at date: Date) -> Data {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return Data("\(type.rawValue) \(dateFormatter.string(from: date))".utf8)
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
