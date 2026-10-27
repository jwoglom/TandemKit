import Foundation
import LoopKit

public extension NewPumpEvent {
    /// `dose` is `bolus` as reported now, under `bolus`'s identity whatever it delivers.
    static func bolus(dose: DoseEntry, of bolus: UnfinalizedDose) -> NewPumpEvent {
        .bolus(dose: dose, date: bolus.startDate, eventRaw: bolus.eventRaw)
    }

    /// Without an `eventRaw`, keyed on the programmed amount: `raw` is the dose's identity, so
    /// finalizing must not change it (#328).
    static func bolus(dose: DoseEntry, date: Date = Date.now, eventRaw: Data? = nil) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: dose,
            raw: eventRaw ?? "\(DoseType.bolus.rawValue) \(dose.programmedUnits) \(dateFormatter.string(from: date))"
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

    /// Keyed on `record`, the identity of the pump's record of it, or else on its type and date.
    static func resume(dose: DoseEntry, date: Date = Date.now, record: Data? = nil) -> NewPumpEvent {
        NewPumpEvent(
            date: date,
            dose: dose,
            raw: record ?? deliveryChangeRaw(.resume, at: date),
            title: String(localized: "Resume", comment: "Pump Event title for UnfinalizedDose with doseType of .resume")
        )
    }

    static func suspend(dose: DoseEntry, date: Date = Date.now, record: Data? = nil) -> NewPumpEvent {
        NewPumpEvent(
            date: date,
            dose: dose,
            raw: record ?? deliveryChangeRaw(.suspend, at: date),
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

    /// Loop derives no doses from reservoir drops within an insulin duration of a `.prime`. The pump
    /// reports no volume for a tubing fill.
    static func tubingPrime(date: Date = Date.now) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: nil,
            raw: "prime tubing \(dateFormatter.string(from: date))".data(using: .utf8) ?? Data([]),
            title: String(localized: "Tubing Fill", comment: "Pump Event title for filling the tubing"),
            type: .prime
        )
    }

    static func cannulaPrime(units: Double, date: Date = Date.now) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: nil,
            raw: "prime cannula \(dateFormatter.string(from: date))".data(using: .utf8) ?? Data([]),
            title: String(
                format: String(localized: "Cannula Fill %@ U", comment: "Pump Event title for filling the cannula; the placeholder is the units primed"),
                String(format: "%g", units)
            ),
            type: .prime
        )
    }

    /// Trio stores it as a site change, as it does a pod's.
    static func pumpReplacement(date: Date = Date.now) -> NewPumpEvent {
        pumpChange(
            "replacePump",
            date: date,
            title: String(localized: "Pump Replaced", comment: "Pump Event title for a different pump paired in place of the last one")
        )
    }

    static func pumpAdded(date: Date = Date.now) -> NewPumpEvent {
        pumpChange(
            "pumpAdded",
            date: date,
            title: String(localized: "Pump Added", comment: "Pump Event title for the first pump a newly added Tandem pump manager paired")
        )
    }

    static func pumpRemoved(date: Date = Date.now) -> NewPumpEvent {
        pumpChange(
            "pumpRemoved",
            date: date,
            title: String(localized: "Pump Removed", comment: "Pump Event title for the Tandem pump being deleted from the app")
        )
    }

    private static func pumpChange(_ kind: String, date: Date, title: String) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: nil,
            raw: "\(kind) \(dateFormatter.string(from: date))".data(using: .utf8) ?? Data([]),
            title: title,
            type: .replaceComponent(componentType: .pump)
        )
    }
}
