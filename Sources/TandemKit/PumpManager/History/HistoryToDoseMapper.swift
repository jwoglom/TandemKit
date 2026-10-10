import Foundation
import LoopKit

/// Maps Tandem history log records to the LoopKit `NewPumpEvent`s that report the boluses in them
/// to the host app. Basal comes from `PumpBasalTimeline`.
///
/// Pure: emitting and reconciling against live reports are the caller's job. Every `raw` is a
/// `HistoryLogSyncIdentifier`, stable however often the window is re-fetched.
final class HistoryToDoseMapper {
    /// Maps one fetched window of history logs to bolus events, in ascending date order.
    ///
    /// - Parameters:
    ///   - dates: Dates each record on the phone's clock, built from the same window.
    ///   - pumpSerial: Serial of the pump the logs came from; part of every identity because
    ///     `bolusId` is a small counter that repeats across pumps. Requiring the validated wrapper
    ///     means no mapping can happen until the serial is actually known.
    ///   - isCommandedBolus: Whether a `bolusId` corresponds to a bolus the controlling app
    ///     commanded (vs a pump-UI Quick Bolus / Control-IQ bolus). Drives
    ///     `DoseEntry.wasProgrammedByPumpUI`.
    func mapToEvents(
        _ logs: [HistoryLog],
        dates: HistoryRecordDates,
        pumpSerial: HistoryLogSyncIdentifier.PumpSerial,
        insulinType: InsulinType?,
        isCommandedBolus: (Int) -> Bool
    ) -> [NewPumpEvent] {
        let sortedLogs = logs.sorted { $0.sequenceNum < $1.sequenceNum }

        let controlIqTriggeredBolusIds = Self.controlIqTriggeredBolusIds(in: sortedLogs)
        var bolusActivations: [Int: BolusActivatedHistoryLog] = [:]
        var events: [NewPumpEvent] = []

        for log in sortedLogs {
            switch log {
            case let activation as BolusActivatedHistoryLog:
                bolusActivations[activation.bolusId] = activation
            case let completion as BolusCompletedHistoryLog:
                events.append(completedBolusEvent(
                    activation: bolusActivations.removeValue(forKey: completion.bolusId),
                    completion: completion,
                    dates: dates,
                    pumpSerial: pumpSerial,
                    insulinType: insulinType,
                    isControlIqTriggered: controlIqTriggeredBolusIds.contains(completion.bolusId),
                    isCommandedBolus: isCommandedBolus
                ))
            default:
                continue
            }
        }

        // Activations with no completion in the window are in flight (or their completion sits
        // in a chunk not fetched yet): mutable, under the identity their completion will carry.
        for activation in bolusActivations.values {
            events.append(inFlightBolusEvent(
                activation,
                dates: dates,
                pumpSerial: pumpSerial,
                insulinType: insulinType,
                isControlIqTriggered: controlIqTriggeredBolusIds.contains(activation.bolusId),
                isCommandedBolus: isCommandedBolus
            ))
        }

        // Dictionary iteration above is unordered, and the host app applies events in the order
        // given; sort so the result is deterministic and ascending.
        return events.sorted { $0.date < $1.date }
    }

    /// Set explicitly because Trio reads a nil `automatic` as an SMB.
    private static func controlIqTriggeredBolusIds(in logs: [HistoryLog]) -> Set<Int> {
        var ids = Set<Int>()
        for log in logs {
            switch log {
            case let delivery as BolusDeliveryHistoryLog where delivery.bolusSourceEnum == .controlIQAutoBolus:
                ids.insert(delivery.bolusID)
            case let request as BolusRequestedMsg2HistoryLog
                where request.bolusOption == .automatic || request.bolusOption == .eatingSoonAutomatic:
                ids.insert(request.bolusId)
            default:
                continue
            }
        }
        return ids
    }

    // MARK: - Event builders

    private func completedBolusEvent(
        activation: BolusActivatedHistoryLog?,
        completion: BolusCompletedHistoryLog,
        dates: HistoryRecordDates,
        pumpSerial: HistoryLogSyncIdentifier.PumpSerial,
        insulinType: InsulinType?,
        isControlIqTriggered: Bool,
        isCommandedBolus: (Int) -> Bool
    ) -> NewPumpEvent {
        let endDate = dates.phoneDate(of: completion)
        let startDate: Date
        if let activation {
            startDate = dates.phoneDate(of: activation)
        } else {
            startDate = endDate
        }

        let raw = HistoryLogSyncIdentifier.bolus(pumpSerial: pumpSerial, bolusId: completion.bolusId)
        let dose = DoseEntry(
            type: .bolus,
            startDate: startDate,
            endDate: endDate,
            value: TandemPumpCapabilities.roundToReportingResolution(activation.map { Double($0.bolusSize) } ?? Double(completion.insulinRequested)),
            unit: .units,
            deliveredUnits: TandemPumpCapabilities.roundToReportingResolution(Double(completion.insulinDelivered)),
            description: "Bolus #\(completion.bolusId)",
            syncIdentifier: raw.hexadecimalString,
            insulinType: insulinType,
            automatic: isControlIqTriggered,
            wasProgrammedByPumpUI: !isCommandedBolus(completion.bolusId)
        )
        // Trio times a bolus's insulin action from the event date.
        return NewPumpEvent(date: dose.startDate, dose: dose, raw: raw, title: "Bolus", type: .bolus)
    }

    private func inFlightBolusEvent(
        _ activation: BolusActivatedHistoryLog,
        dates: HistoryRecordDates,
        pumpSerial: HistoryLogSyncIdentifier.PumpSerial,
        insulinType: InsulinType?,
        isControlIqTriggered: Bool,
        isCommandedBolus: (Int) -> Bool
    ) -> NewPumpEvent {
        let startDate = dates.phoneDate(of: activation)
        let raw = HistoryLogSyncIdentifier.bolus(pumpSerial: pumpSerial, bolusId: activation.bolusId)
        let dose = DoseEntry(
            type: .bolus,
            startDate: startDate,
            value: TandemPumpCapabilities.roundToReportingResolution(Double(activation.bolusSize)),
            unit: .units,
            description: "Bolus #\(activation.bolusId)",
            syncIdentifier: raw.hexadecimalString,
            insulinType: insulinType,
            automatic: isControlIqTriggered,
            isMutable: true,
            wasProgrammedByPumpUI: !isCommandedBolus(activation.bolusId)
        )
        return NewPumpEvent(date: dose.startDate, dose: dose, raw: raw, title: "Bolus", type: .bolus)
    }
}
