import Foundation
import LoopKit

/// Maps Tandem history log records to the LoopKit `NewPumpEvent`s that report the boluses in them
/// to the host app. Basal comes from `PumpBasalTimeline`.
///
/// An extended bolus is two doses under one `bolusId`: the up-front part, 55 to a 20 that counts it
/// alone (none when 100% extended), and the extended part, 59 to 21, under `extendedBolus`.
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
        let extendedDurations = Self.extendedDurations(in: sortedLogs)
        var bolusActivations: [Int: BolusActivatedHistoryLog] = [:]
        var bolexActivations: [Int: BolexActivatedHistoryLog] = [:]
        var upFrontDates: [Int: Date] = [:]
        var events: [NewPumpEvent] = []

        for log in sortedLogs {
            switch log {
            case let activation as BolusActivatedHistoryLog:
                bolusActivations[activation.bolusId] = activation
                upFrontDates[activation.bolusId] = dates.phoneDate(of: activation)
            case let completion as BolusCompletedHistoryLog:
                let event = completedBolusEvent(
                    activation: bolusActivations.removeValue(forKey: completion.bolusId),
                    completion: completion,
                    dates: dates,
                    pumpSerial: pumpSerial,
                    insulinType: insulinType,
                    isControlIqTriggered: controlIqTriggeredBolusIds.contains(completion.bolusId),
                    isCommandedBolus: isCommandedBolus
                )
                upFrontDates[completion.bolusId] = event.date
                events.append(event)
            case let activation as BolexActivatedHistoryLog:
                bolexActivations[activation.bolusId] = activation
            case let completion as BolexCompletedHistoryLog:
                // A 21 carries no start, so without its 59 the dose can't be placed in time.
                guard let activation = bolexActivations.removeValue(forKey: completion.bolusId) else {
                    continue
                }
                events.append(extendedPartEvent(
                    activation,
                    completion: completion,
                    programmedDuration: extendedDurations[activation.bolusId],
                    upFrontDate: upFrontDates[activation.bolusId],
                    dates: dates,
                    pumpSerial: pumpSerial,
                    insulinType: insulinType,
                    isControlIqTriggered: controlIqTriggeredBolusIds.contains(activation.bolusId),
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

        for activation in bolexActivations.values {
            events.append(extendedPartEvent(
                activation,
                completion: nil,
                programmedDuration: extendedDurations[activation.bolusId],
                upFrontDate: upFrontDates[activation.bolusId],
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

    /// `BolusDeliveryHistoryLog.extendedDurationRequested` is in minutes; every 280 of a bolus repeats it.
    private static func extendedDurations(in logs: [HistoryLog]) -> [Int: TimeInterval] {
        var durations: [Int: TimeInterval] = [:]
        for case let delivery as BolusDeliveryHistoryLog in logs where delivery.extendedDurationRequested > 0 {
            durations[delivery.bolusID] = .minutes(Double(delivery.extendedDurationRequested))
        }
        return durations
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

    /// Ends at its 21 with what it delivered, however it ended; mutable over its programmed duration until then.
    private func extendedPartEvent(
        _ activation: BolexActivatedHistoryLog,
        completion: BolexCompletedHistoryLog?,
        programmedDuration: TimeInterval?,
        upFrontDate: Date?,
        dates: HistoryRecordDates,
        pumpSerial: HistoryLogSyncIdentifier.PumpSerial,
        insulinType: InsulinType?,
        isControlIqTriggered: Bool,
        isCommandedBolus: (Int) -> Bool
    ) -> NewPumpEvent {
        var startDate = dates.phoneDate(of: activation)
        // 59 can fall in its up-front part's second, and Trio matches a new row on its timestamp.
        if let upFrontDate, startDate <= upFrontDate {
            startDate = upFrontDate.addingTimeInterval(1)
        }
        let endDate: Date
        if let completion {
            endDate = max(dates.phoneDate(of: completion), startDate)
        } else {
            // Without its 280 it counts at its start: early, so IOB is overstated rather than missed.
            endDate = startDate.addingTimeInterval(programmedDuration ?? 0)
        }

        let raw = HistoryLogSyncIdentifier.extendedBolus(pumpSerial: pumpSerial, bolusId: activation.bolusId)
        let dose = DoseEntry(
            type: .bolus,
            startDate: startDate,
            endDate: endDate,
            value: TandemPumpCapabilities.roundToReportingResolution(Double(activation.bolexSize)),
            unit: .units,
            deliveredUnits: completion.map { TandemPumpCapabilities.roundToReportingResolution(Double($0.insulinDelivered)) },
            description: "Extended bolus #\(activation.bolusId)",
            syncIdentifier: raw.hexadecimalString,
            insulinType: insulinType,
            automatic: isControlIqTriggered,
            isMutable: completion == nil,
            wasProgrammedByPumpUI: !isCommandedBolus(activation.bolusId)
        )
        return NewPumpEvent(date: startDate, dose: dose, raw: raw, title: "Extended Bolus", type: .bolus)
    }
}
