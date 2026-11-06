import Foundation
import LoopAlgorithm
import LoopKit
@testable import TandemKit
import XCTest

/// Replays `hasNewPumpEvents` batches with the semantics of LoopKit's `DoseStore.addPumpEvents` and
/// the `InsulinDeliveryStore.addDoseEntries(resolveMutable: true)` it always ends in.
///
/// Every rule is a fold over two in-memory tables that stand in for the two Core Data tiers:
///
/// - `pumpEvents`: the `PumpEvent` rows (one per `NewPumpEvent`, keyed on `raw`).
/// - `cachedDoses`: the `CachedInsulinDeliveryObject` rows (one per dose, keyed on `syncIdentifier`,
///   which `NewPumpEvent.init` derives from `raw`). Only these reach HealthKit and IOB.
///
/// The file references below are to Trio's LoopKit fork, the one TandemKit links:
/// `LoopKit/LoopKit/InsulinKit/DoseStore.swift` (DS), `InsulinDeliveryStore.swift` (IDS),
/// `CachedInsulinDeliveryObject+CoreDataClass.swift` (CIDO), `HKQuantitySample+InsulinKit.swift` (HKQS),
/// `InsulinMath.swift` (IM), `LoopKit/LoopKit/Persistence/Model.xcdatamodeld/Model.xcdatamodel/contents`
/// (Model) and `PersistenceController.swift` (PC), in the Trio workspace's `LoopKit` submodule when
/// written. Upstream LoopKit, which Loop builds, has the same code in each. The save to the IDS
/// follows LoopKit `next-dev` (`b6db6e18`), which Loop `next-dev` builds and Trio's fork now tracks;
/// its references are marked `next-dev`.
///
/// What is deliberately not modelled, and why:
/// - The basal-schedule overlay (DS:992-999), unless `basalSchedule` is given. For a pump that does
///   not record basal profile starts, TandemKit among them, DoseStore fills every gap between basal
///   doses with the schedule's rate. Those entries move `lastImmutableBasalEndDate`, so Loop in the
///   simulator needs them; the conformance groups leave them out.
/// - The cache window purge (DS:714). Tests run over minutes, not days.
/// - IDS skipping a temp basal with no duration, as it does a basal (HKQS:56-60). On a conformance
///   run's manual clock a temp can end where it started, and `PumpTimeline` wants a dose for it.
/// - Core Data itself. The two uniqueness constraints that matter are modelled explicitly (see
///   `insertPumpEventRow` and `insertCachedDose`) because they decide whether a re-report updates or
///   is dropped.
final class LoopDoseStoreOracle: DoseOracle {
    /// One `PumpEvent` row (DS:735-744).
    struct PumpEventRow: Equatable {
        let raw: Data
        let date: Date
        let type: PumpEventType?
        let mutable: Bool
        let dose: DoseEntry?
        let title: String
    }

    /// One `CachedInsulinDeliveryObject` (CIDO:208-253). `dose` is the entry it was last created or
    /// updated from; `value` is what Loop's IOB reads (`unitsInDeliverableIncrements`, CIDO:217/241).
    struct StoredDose: Equatable {
        let syncIdentifier: String
        let provenanceIdentifier: String
        var dose: DoseEntry
        var isMutable: Bool
        /// Soft-deleted at this instant; a dose is live while nil (IDS:430-436, CIDO:222/245).
        var deletedAt: Date?
        let createdAt: Date
        /// Written to HealthKit at least once. Only immutable doses get there (IDS:476).
        var savedToHealthKit: Bool
        /// How many `update(from:)` calls the object has taken since creation.
        var updateCount: Int

        var raw: Data? { Data(hexadecimalString: syncIdentifier) }
        var value: Double { dose.unitsInDeliverableIncrements }
        var isDeleted: Bool { deletedAt != nil }
    }

    /// `InsulinDeliveryStore.provenanceIdentifier` is the app's bundle identifier; any constant will do
    /// as long as every batch is fed by the same host (IDS:455 matches on it).
    let provenanceIdentifier: String
    /// `DoseStore.cacheLength` (DS:196, 24 h) bounds how far back boluses are re-sent to the IDS.
    let cacheLength: TimeInterval
    /// Duration of the linear-decay IOB curve in `iob(at:)`.
    let insulinActionDuration: TimeInterval
    /// The host's basal schedule, for the overlay.
    let basalSchedule: BasalRateSchedule?

    private(set) var pumpEvents: [PumpEventRow] = []
    private(set) var cachedDoses: [StoredDose] = []
    /// `DoseStore.lastPumpEventsReconciliation` (DS:680).
    private(set) var lastReconciliation: Date?
    /// `DoseStore.pumpEventQueryAfterDate` (DS:747-754).
    private(set) var pumpEventQueryAfterDate: Date?
    /// Number of `addPumpEvents` calls, including empty batches.
    private(set) var callCount = 0
    /// Every value `lastReconciliation` has taken, in call order (nil recorded as nil).
    private(set) var reconciliationHistory: [Date?] = []

    init(
        provenanceIdentifier: String = "org.nightscoutfoundation.tandemkit.conformance",
        cacheLength: TimeInterval = .hours(24),
        insulinActionDuration: TimeInterval = .hours(5),
        basalSchedule: BasalRateSchedule? = nil
    ) {
        self.provenanceIdentifier = provenanceIdentifier
        self.cacheLength = cacheLength
        self.insulinActionDuration = insulinActionDuration
        self.basalSchedule = basalSchedule
    }

    // MARK: - Views

    /// Live doses (not soft-deleted), oldest created first.
    var doses: [StoredDose] { cachedDoses.filter { !$0.isDeleted } }
    /// Soft-deleted doses, oldest created first.
    var deletedDoses: [StoredDose] { cachedDoses.filter(\.isDeleted) }
    var mutableDoses: [StoredDose] { doses.filter(\.isMutable) }
    var permanentDoses: [StoredDose] { doses.filter { !$0.isMutable } }

    /// Every cached dose, live or deleted, that was created from an event with this `raw`.
    func cachedDoses(raw: Data) -> [StoredDose] {
        cachedDoses.filter { $0.syncIdentifier == raw.hexadecimalString }
    }

    /// The live dose for this `raw`, if there is exactly one.
    func dose(raw: Data) -> StoredDose? {
        let live = doses.filter { $0.syncIdentifier == raw.hexadecimalString }
        return live.count == 1 ? live[0] : nil
    }

    func pumpEventRow(raw: Data) -> PumpEventRow? {
        pumpEvents.first { $0.raw == raw }
    }

    // MARK: - DoseStore.addPumpEvents (DS:679-769)

    func addPumpEvents(_ events: [NewPumpEvent], lastReconciliation: Date?, replacePendingEvents: Bool, now: Date) {
        callCount += 1

        // DS:680 — set unconditionally, before the empty guard, on every call.
        self.lastReconciliation = lastReconciliation
        reconciliationHistory.append(lastReconciliation)

        // next-dev DS:626-629 — an empty batch stores no rows but still re-saves to the IDS.
        guard !events.isEmpty else {
            syncPumpEventsToInsulinDeliveryStore(now: now)
            return
        }

        // DS:704-706 — replacePendingEvents purges every mutable PumpEvent row first.
        if replacePendingEvents {
            pumpEvents.removeAll(where: \.mutable)
        }

        // DS:714 cache-window purge: not modelled (see the type comment).

        // DS:720-745 — insert each event as a PumpEvent row, tracking the date boundaries.
        var lastFinalDate: Date?
        var firstMutableDate: Date?
        for event in events {
            let isMutable = event.dose?.isMutable == true
            if isMutable {
                firstMutableDate = min(event.date, firstMutableDate ?? event.date)
            } else {
                lastFinalDate = max(event.date, lastFinalDate ?? event.date)
            }
            insertPumpEventRow(PumpEventRow(
                raw: event.raw,
                date: event.date,
                type: event.type,
                mutable: isMutable,
                dose: event.dose,
                title: event.title
            ))
        }

        // DS:747-754 — the upload cursor moves only on finalized records, and is pulled back to the
        // earliest mutable date when one predates the newest final one.
        if let finalDate = lastFinalDate {
            if let mutableDate = firstMutableDate, mutableDate < finalDate {
                pumpEventQueryAfterDate = mutableDate
            } else {
                pumpEventQueryAfterDate = finalDate
            }
        }

        // DS:761-762 — after the save, always syncPumpEventsToInsulinDeliveryStore(resolveMutable: true).
        syncPumpEventsToInsulinDeliveryStore(now: now)
    }

    /// `PumpEvent` has a uniqueness constraint on `raw` (Model:123) and the context's merge policy is
    /// `NSMergeByPropertyStoreTrumpMergePolicy` (PC:128): inserting a row whose `raw` already exists
    /// keeps the stored row's values. A re-report therefore only takes effect when the old row was
    /// purged first — which is what `replacePendingEvents == true` does for mutable rows.
    private func insertPumpEventRow(_ row: PumpEventRow) {
        guard !pumpEvents.contains(where: { $0.raw == row.raw }) else { return }
        pumpEvents.append(row)
    }

    // MARK: - DoseStore.syncPumpEventsToInsulinDeliveryStore (DS:911-1002, 1123-1143)

    /// Every non-empty `addPumpEvents`, from whichever pump manager, runs it, as does `addDoses`
    /// (DS:857); a test calls it directly for the host's next one.
    func syncPumpEventsToInsulinDeliveryStore(now: Date) {
        // next-dev DS:840-855 — start at the IDS's last immutable basal end date, or with none at the
        // oldest pump event, but no earlier than a day ago.
        let firstEvent = pumpEvents.min { $0.date < $1.date }.map { $0.dose?.startDate ?? $0.date }
        guard let since = lastImmutableBasalEndDate ?? firstEvent else { return }
        let start = max(since, now.addingTimeInterval(-cacheLength))

        // next-dev DS:888-894 — nothing is saved without a reconciliation boundary; one before `start`
        // is only logged.
        guard let endingAt = lastReconciliation else { return }

        // DS:1128-1136 — every basal-type dose since start (minus the reconciliation window, which
        // only matters for the un-modelled reconcile) plus every bolus in the cache window.
        let recentStart = now.addingTimeInterval(-cacheLength)
        let candidates = pumpEvents.compactMap { row -> DoseEntry? in
            guard let dose = row.dose else { return nil }
            if dose.type == .bolus { return row.date >= recentStart ? dose : nil }
            return row.date >= start.addingTimeInterval(-cacheLength) ? dose : nil
        }
        // DS:1140 — reconcile suspend/resume and basal succession, then drop doses that have not
        // ended yet unless they are mutable, then those before start unless they are boluses.
        let doses = Self.reconciled(candidates.sorted { $0.startDate < $1.startDate })
            .filter { $0.endDate <= now || $0.isMutable }
            .filter { $0.startDate >= start || $0.type == .bolus }

        // next-dev DS:903-906, then DS:867-870: the overlay can save schedule pieces with no dose.
        let overlaid = basalSchedule.map { Self.overlaying(doses, with: $0, from: start, to: endingAt) } ?? doses
        guard !overlaid.isEmpty else { return }
        addDoseEntries(overlaid, resolveMutable: true, now: now)
    }

    /// next-dev IM:273-352 `overlayBasal(_:endDate: end, lastPumpEventsReconciliation: end)` over the
    /// schedule's rates from `start` to `end` (SettingsStore.getBasalHistory truncates them to the save):
    /// the schedule's rate in each gap before a basal, temp basal or suspend and after the last one, each
    /// piece keyed on its start, the piece reaching `end` left mutable.
    ///
    /// next-dev IM:333-335 also stretches a suspend that is the last basal dose to `end`, meant for one
    /// still open, but applies it to one its resume closed too (LoopKit/LoopKit#688). This models the
    /// intended rule, so Loop's stored suspend differs until LoopKit is fixed.
    static func overlaying(_ doses: [DoseEntry], with schedule: BasalRateSchedule, from start: Date, to end: Date) -> [DoseEntry] {
        let timeline = scheduledRates(schedule, from: start, to: end)
            .map { (start: max($0.start, start), end: min($0.end, end), rate: $0.rate) }
            .filter { $0.end > $0.start }
        guard let first = timeline.first else { return doses }

        let formatter = ISO8601DateFormatter()
        var entries: [DoseEntry] = []
        var index = timeline.startIndex
        var lastDate = first.start

        func addBasals(from pieceStart: Date, to pieceEnd: Date) {
            while lastDate < pieceEnd {
                let entryEnd: Date
                let rate = timeline[index].rate
                if index + 1 < timeline.endIndex, timeline[index + 1].start < pieceEnd {
                    entryEnd = max(pieceStart, timeline[index + 1].start)
                    index += 1
                } else {
                    entryEnd = pieceEnd
                }
                if lastDate != entryEnd {
                    entries.append(DoseEntry(
                        type: .basal,
                        startDate: lastDate,
                        endDate: entryEnd,
                        value: rate,
                        unit: .unitsPerHour,
                        decisionId: nil,
                        syncIdentifier: "BasalRateSchedule \(formatter.string(from: lastDate))",
                        scheduledBasalRate: LoopQuantity(unit: .internationalUnitsPerHour, doubleValue: rate),
                        automatic: nil,
                        isMutable: entryEnd >= end
                    ))
                    lastDate = entryEnd
                }
            }
        }

        for (position, dose) in doses.enumerated() {
            switch dose.type {
            case .basal, .tempBasal, .suspend:
                if dose.startDate > lastDate {
                    addBasals(from: lastDate, to: dose.startDate)
                }
                var placed = dose
                placed.startDate = lastDate
                if dose.type == .suspend, dose.isMutable, position + 1 == doses.count, dose.endDate < end {
                    placed.endDate = end
                }
                entries.append(placed)
                lastDate = placed.endDate
            case .bolus:
                entries.append(dose)
            case .resume:
                break
            }
        }
        if end > lastDate {
            addBasals(from: lastDate, to: end)
        }
        return entries
    }

    /// DailyValueSchedule.swift:126-187 `between(start:end:)`: every item that overlaps `start...end`, on
    /// the dates it covers in the schedule's own time zone.
    static func scheduledRates(
        _ schedule: BasalRateSchedule,
        from startDate: Date,
        to endDate: Date
    ) -> [(start: Date, end: Date, rate: Double)] {
        let items = schedule.items
        guard startDate <= endDate, endDate.timeIntervalSince(startDate).isFinite, let first = items.first else {
            return []
        }
        let repeatInterval = TimeInterval.hours(24)
        let referenceTime = first.startTime
        let maxTime = referenceTime + repeatInterval
        func offset(of date: Date) -> TimeInterval {
            let interval = date.timeIntervalSinceReferenceDate + TimeInterval(schedule.timeZone.secondsFromGMT(for: date))
            return (interval - referenceTime).truncatingRemainder(dividingBy: repeatInterval) + referenceTime
        }
        func within(_ start: Date, from startOffset: TimeInterval, to endOffset: TimeInterval) -> [(start: Date, end: Date, rate: Double)] {
            var startIndex = 0
            var endIndex = items.count
            for (index, item) in items.enumerated() {
                if startOffset >= item.startTime {
                    startIndex = index
                }
                if endOffset < item.startTime {
                    endIndex = index
                    break
                }
            }
            let reference = start.addingTimeInterval(-startOffset)
            return (startIndex ..< endIndex).map { index in
                let endTime = index + 1 < items.count ? items[index + 1].startTime : maxTime
                return (reference.addingTimeInterval(items[index].startTime), reference.addingTimeInterval(endTime), items[index].value)
            }
        }
        var values: [(start: Date, end: Date, rate: Double)] = []
        var start = startDate
        while true {
            let startOffset = offset(of: start)
            let endOffset = startOffset + endDate.timeIntervalSince(start)
            guard endOffset > maxTime else {
                return values + within(start, from: startOffset, to: endOffset)
            }
            values += within(start, from: startOffset, to: maxTime)
            start = start.addingTimeInterval(maxTime - startOffset)
        }
    }

    /// `Array<DoseEntry>.reconciled()` (IM:396-522), applied to the pump-event doses in chronological
    /// order before they reach the IDS: a basal or temp basal is trimmed to the start of the next one
    /// (IM:408-414) or of a suspend (IM:480-497); a suspend is closed by the next resume (IM:435-451)
    /// or by a temp basal arriving with no resume (IM:415-431); a temp basal interrupted by a suspend
    /// continues after the resume under the resume's identifier (IM:454-470); an unpaired suspend is
    /// emitted open and mutable regardless of what the driver said (IM:503-516); a trailing basal
    /// with no duration is dropped (IM:517-519). Finally every immutable dose without a
    /// `deliveredUnits` gets one resolved from its programmed amount (IM:345-365 `resolvingDelivery`).
    static func reconciled(_ doses: [DoseEntry]) -> [DoseEntry] {
        var reconciled: [DoseEntry] = []
        var lastSuspend: DoseEntry?
        var lastBasal: DoseEntry?

        for dose in doses {
            switch dose.type {
            case .bolus:
                reconciled.append(dose)
            case .basal, .tempBasal:
                if lastSuspend == nil, let last = lastBasal {
                    let endDate = min(last.endDate, dose.startDate)
                    if endDate > last.startDate, let trimmed = last.trimmed(from: nil, to: endDate, syncIdentifier: last.syncIdentifier) {
                        reconciled.append(trimmed)
                    }
                } else if let suspend = lastSuspend, dose.type == .tempBasal {
                    reconciled.append(Self.closing(suspend, at: dose.startDate))
                    lastSuspend = nil
                }
                lastBasal = dose
            case .resume:
                if let suspend = lastSuspend {
                    reconciled.append(Self.closing(suspend, at: dose.startDate))
                    lastSuspend = nil
                    if let last = lastBasal {
                        if last.endDate > dose.endDate {
                            lastBasal = DoseEntry(
                                type: last.type,
                                startDate: dose.endDate,
                                endDate: last.endDate,
                                value: Self.programmedValue(last),
                                unit: last.unit,
                                decisionId: nil,
                                description: last.description,
                                syncIdentifier: dose.syncIdentifier,
                                insulinType: last.insulinType,
                                automatic: last.automatic,
                                isMutable: last.isMutable,
                                wasProgrammedByPumpUI: last.wasProgrammedByPumpUI
                            )
                        } else {
                            lastBasal = nil
                        }
                    }
                }
            case .suspend:
                if let last = lastBasal {
                    reconciled.append(DoseEntry(
                        type: last.type,
                        startDate: last.startDate,
                        endDate: min(last.endDate, dose.startDate),
                        value: Self.programmedValue(last),
                        unit: last.unit,
                        decisionId: nil,
                        description: last.description,
                        syncIdentifier: last.syncIdentifier,
                        insulinType: last.insulinType,
                        automatic: last.automatic,
                        isMutable: last.isMutable,
                        wasProgrammedByPumpUI: last.wasProgrammedByPumpUI
                    ))
                    if last.endDate <= dose.startDate {
                        lastBasal = nil
                    }
                }
                lastSuspend = dose
            }
        }

        if let suspend = lastSuspend {
            reconciled.append(DoseEntry(
                type: suspend.type,
                startDate: suspend.startDate,
                endDate: nil,
                value: Self.programmedValue(suspend),
                unit: suspend.unit,
                decisionId: nil,
                description: suspend.description,
                syncIdentifier: suspend.syncIdentifier,
                insulinType: suspend.insulinType,
                automatic: suspend.automatic,
                isMutable: true, // IM:514 "Consider mutable until paired resume"
                wasProgrammedByPumpUI: suspend.wasProgrammedByPumpUI
            ))
        } else if let last = lastBasal, last.endDate > last.startDate {
            reconciled.append(last)
        }

        return reconciled.map(Self.resolvingDelivery)
    }

    /// `DoseEntry.value` is internal in the fork; this is it, read back through the public accessors
    /// (`programmedUnits` returns `value` for `.units`, `unitsPerHour` returns it for `.unitsPerHour`).
    static func programmedValue(_ dose: DoseEntry) -> Double {
        switch dose.unit {
        case .units: return dose.programmedUnits
        case .unitsPerHour: return dose.unitsPerHour
        }
    }

    /// IM:417-429 / IM:437-449: the suspend dose closed at `end`.
    private static func closing(_ suspend: DoseEntry, at end: Date) -> DoseEntry {
        DoseEntry(
            type: suspend.type,
            startDate: suspend.startDate,
            endDate: end,
            value: Self.programmedValue(suspend),
            unit: suspend.unit,
            decisionId: nil,
            description: suspend.description,
            syncIdentifier: suspend.syncIdentifier,
            insulinType: suspend.insulinType,
            automatic: suspend.automatic,
            isMutable: suspend.isMutable,
            wasProgrammedByPumpUI: suspend.wasProgrammedByPumpUI
        )
    }

    /// IM:345-365 `resolvingDelivery`.
    private static func resolvingDelivery(_ dose: DoseEntry) -> DoseEntry {
        guard !dose.isMutable, dose.deliveredUnits == nil else { return dose }
        let resolvedUnits: Double
        if case .units = dose.unit {
            resolvedUnits = Self.programmedValue(dose)
        } else {
            switch dose.type {
            case .tempBasal: resolvedUnits = dose.unitsInDeliverableIncrements
            case .basal: resolvedUnits = dose.programmedUnits
            default: return dose
            }
        }
        return DoseEntry(
            type: dose.type,
            startDate: dose.startDate,
            endDate: dose.endDate,
            value: Self.programmedValue(dose),
            unit: dose.unit,
            decisionId: nil,
            deliveredUnits: resolvedUnits,
            description: dose.description,
            syncIdentifier: dose.syncIdentifier,
            scheduledBasalRate: dose.scheduledBasalRate,
            insulinType: dose.insulinType,
            automatic: dose.automatic,
            isMutable: dose.isMutable,
            wasProgrammedByPumpUI: dose.wasProgrammedByPumpUI
        )
    }

    /// `InsulinDeliveryStore.lastImmutableBasalEndDate` (IDS:373-396): the newest end date among live,
    /// immutable, basal-reason (non-bolus, CIDO:220) doses of LoopKit origin; nil if none.
    private var lastImmutableBasalEndDate: Date? {
        doses
            .filter { !$0.isMutable && $0.dose.type != .bolus }
            .map(\.dose.endDate)
            .max()
    }

    // MARK: - InsulinDeliveryStore.addDoseEntries(resolveMutable:) (IDS:412-507)

    private func addDoseEntries(_ entries: [DoseEntry], resolveMutable: Bool, now: Date) {
        // IDS:413 — guard !entries.isEmpty.
        guard !entries.isEmpty else { return }

        // IDS:428-436 — fetch every live mutable object and mark it deleted up front.
        var mutableIndices: [Int] = []
        if resolveMutable {
            for index in cachedDoses.indices where !cachedDoses[index].isDeleted && cachedDoses[index].isMutable {
                cachedDoses[index].deletedAt = now
                mutableIndices.append(index)
            }
        }

        for entry in entries {
            // IDS:438-441 — entries without a syncIdentifier are ignored.
            guard let syncIdentifier = entry.syncIdentifier else { continue }
            // IDS:443-452 — nor is one that makes no HealthKit sample: a basal with no duration (HKQS:56-60),
            // such as the driver's scheduled-basal marker before a suspend.
            if entry.type == .basal, entry.endDate.timeIntervalSince(entry.startDate) <= .ulpOfOne { continue }
            // HKQS:73-77 — or a 0 U bolus, whose mutable copy stays deleted: Loop's end state for a dose
            // that never happened.
            if entry.type == .bolus, entry.unitsInDeliverableIncrements <= .ulpOfOne { continue }

            // IDS:455-459 — a mutable object with the same provenance + syncIdentifier is updated,
            // which also un-deletes it (CIDO:245 `deletedAt = nil`).
            if let index = mutableIndices.first(where: {
                cachedDoses[$0].provenanceIdentifier == provenanceIdentifier &&
                    cachedDoses[$0].syncIdentifier == syncIdentifier
            }) {
                update(&cachedDoses[index], from: entry, now: now)
            } else {
                // IDS:462-466 — otherwise a new object is created.
                insertCachedDose(StoredDose(
                    syncIdentifier: syncIdentifier,
                    provenanceIdentifier: provenanceIdentifier,
                    dose: entry,
                    isMutable: entry.isMutable,
                    deletedAt: nil,
                    createdAt: now,
                    savedToHealthKit: !entry.isMutable,
                    updateCount: 0
                ))
            }
        }
        // IDS:469-473 — anything still marked deleted at this point is logged as "Delete"; that is the
        // report-or-delete rule taking effect for doses the batch stopped sending.
    }

    /// CIDO:232-253 `update(from:)`.
    private func update(_ stored: inout StoredDose, from entry: DoseEntry, now _: Date) {
        stored.dose = entry
        stored.isMutable = entry.isMutable
        stored.deletedAt = nil
        stored.updateCount += 1
        // IDS:476 — only immutable objects are written to HealthKit.
        if !entry.isMutable {
            stored.savedToHealthKit = true
        }
    }

    /// `CachedInsulinDeliveryObject` has a uniqueness constraint on `syncIdentifier` (Model:82) under
    /// the same store-trump merge policy (PC:128): a second object for an identifier that already
    /// exists — live or soft-deleted, mutable or not — is dropped and the stored one stands. This is
    /// why an immutable dose re-sent in later batches is harmless, and why a dose whose mutable
    /// object was soft-deleted cannot be resurrected by an insert, only by a mutable match.
    private func insertCachedDose(_ dose: StoredDose) {
        guard !cachedDoses.contains(where: { $0.syncIdentifier == dose.syncIdentifier }) else { return }
        cachedDoses.append(dose)
    }

    // MARK: - DoseStore.getNormalizedDoseEntries (DS:1198-1240)

    /// What Loop's IOB reads: the stored doses, then those of `PumpEvent` rows reaching `lastReconciliation`
    /// (DS:1086-1096) under an identifier not stored (IM:957-972), so a finalized dose counts before it ends
    /// and can be stored. Reservoir doses (DS:1217) are not modelled.
    func normalizedDoses(from start: Date = .distantPast) -> [DoseEntry] {
        let filteredStart = max(lastReconciliation ?? start, start)
        let pumpEventDoses = Self.reconciled(pumpEvents.compactMap(\.dose).sorted { $0.startDate < $1.startDate })
            .filter { $0.endDate >= filteredStart }
        var identifiers = Set<String>()
        return (doses.map(\.dose) + pumpEventDoses).filter { dose in
            dose.syncIdentifier.map { identifiers.insert($0).inserted } ?? true
        }
    }

    // MARK: - IOB

    /// Insulin on board from the live doses, with each unit decaying linearly to zero over
    /// `insulinActionDuration`. Boluses and temp basals count their stored `value` spread evenly over
    /// `startDate...endDate` (a bolus with equal dates counts at once); scheduled basal, suspends and
    /// resumes count zero. This is a drift detector for duplicate or vanished doses, not a
    /// pharmacokinetic model — compare it across calls, not against Loop's number.
    func iob(at time: Date) -> Double {
        doses.reduce(0) { total, stored in total + Self.linearIOB(of: stored.dose, at: time, duration: insulinActionDuration) }
    }

    /// Basal Loop counts from `start` to `end` above (or, negative, below) `scheduledRate`: each live
    /// temp basal at its stored units spread over its span, each suspend at zero, the schedule elsewhere.
    func netBasalUnits(from start: Date, to end: Date, scheduledRate: (Date) -> Double) -> Double {
        doses.reduce(0) { total, stored in
            let dose = stored.dose
            guard dose.type == .tempBasal || dose.type == .suspend else { return total }
            let lo = max(dose.startDate, start)
            let hi = min(dose.endDate, end)
            let span = dose.endDate.timeIntervalSince(dose.startDate)
            guard hi > lo, span > 0 else { return total }
            let rate = dose.type == .tempBasal ? stored.value / (span / .hours(1)) : 0
            return total + TrioDoseStoreOracle.integrate(from: lo, to: hi) { rate - scheduledRate($0) }
        }
    }

    static func linearIOB(of dose: DoseEntry, at time: Date, duration: TimeInterval) -> Double {
        let units: Double
        switch dose.type {
        case .bolus, .tempBasal: units = dose.unitsInDeliverableIncrements
        case .basal, .suspend, .resume: return 0
        }
        guard units > 0, time > dose.startDate else { return 0 }
        let start = dose.startDate.timeIntervalSinceReferenceDate
        let end = max(dose.endDate.timeIntervalSinceReferenceDate, start)
        let t = time.timeIntervalSinceReferenceDate
        if end == start {
            return units * max(0, 1 - (t - start) / duration)
        }
        // Delivery at rate units/(end-start) over [start, end]; integrate the decay kernel over the
        // part of that window inside [t - duration, t].
        let lo = max(start, t - duration)
        let hi = min(end, t)
        guard hi > lo else { return 0 }
        let rate = units / (end - start)
        let integral = (hi - lo) - ((t - lo) * (t - lo) - (t - hi) * (t - hi)) / (2 * duration)
        return rate * integral
    }

    // MARK: - Assertions

    /// Exactly one live dose exists for `raw`, and no other live dose shares its start date and type
    /// (a re-keyed report of the same dose). Returns it for further checks.
    @discardableResult
    func assertSingleDose(raw: Data, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) -> StoredDose? {
        let identifier = raw.hexadecimalString
        let matching = doses.filter { $0.syncIdentifier == identifier }
        guard matching.count == 1, let dose = matching.first else {
            XCTFail(
                "expected exactly one live dose for raw \(Self.describe(raw)), found \(matching.count); "
                    + "live: \(doses.map(Self.describe)); deleted: \(deletedDoses.map(Self.describe)). \(message)",
                file: file,
                line: line
            )
            return nil
        }
        let lookalikes = doses.filter {
            $0.syncIdentifier != identifier && $0.dose.type == dose.dose.type && $0.dose.startDate == dose.dose.startDate
        }
        XCTAssertTrue(
            lookalikes.isEmpty,
            "dose \(Self.describe(raw)) is duplicated under other identities: \(lookalikes.map(Self.describe)). \(message)",
            file: file,
            line: line
        )
        return dose
    }

    /// No two live doses of the same type overlap in time with the same start date. Two identities for
    /// one delivery is how a changed `raw` shows up.
    func assertNoDuplicates(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        var seen: [String: StoredDose] = [:]
        for stored in doses {
            let key = "\(stored.dose.type.rawValue)|\(stored.dose.startDate.timeIntervalSinceReferenceDate)"
            if let earlier = seen[key] {
                XCTFail(
                    "duplicate \(stored.dose.type) doses at \(stored.dose.startDate): \(Self.describe(earlier)) and \(Self.describe(stored)). \(message)",
                    file: file,
                    line: line
                )
            } else {
                seen[key] = stored
            }
        }
    }

    /// The dose for `raw` is live, immutable, and reached HealthKit — finalized in the guide's sense.
    @discardableResult
    func assertPermanent(raw: Data, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) -> StoredDose? {
        guard let dose = assertSingleDose(raw: raw, message, file: file, line: line) else { return nil }
        XCTAssertFalse(dose.isMutable, "dose \(Self.describe(raw)) is still mutable. \(message)", file: file, line: line)
        XCTAssertTrue(dose.savedToHealthKit, "dose \(Self.describe(raw)) never reached HealthKit. \(message)", file: file, line: line)
        XCTAssertNotNil(
            pumpEventRow(raw: raw),
            "no PumpEvent row for \(Self.describe(raw)); the finalizing event never landed. \(message)",
            file: file,
            line: line
        )
        XCTAssertEqual(pumpEventRow(raw: raw)?.mutable, false, "PumpEvent row for \(Self.describe(raw)) is still mutable. \(message)", file: file, line: line)
        return dose
    }

    /// The dose for `raw` was stored once and is now soft-deleted — the guide's "never happened" transition.
    func assertDeleted(raw: Data, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let all = cachedDoses(raw: raw)
        XCTAssertFalse(all.isEmpty, "dose \(Self.describe(raw)) was never stored. \(message)", file: file, line: line)
        XCTAssertTrue(all.allSatisfy(\.isDeleted), "dose \(Self.describe(raw)) is still live: \(all.map(Self.describe)). \(message)", file: file, line: line)
    }

    static func describe(_ raw: Data) -> String {
        String(decoding: raw, as: UTF8.self)
    }

    static func describe(_ stored: StoredDose) -> String {
        let raw = stored.raw.map(describe) ?? stored.syncIdentifier
        var flags: [String] = []
        if stored.isMutable { flags.append("mutable") }
        if stored.isDeleted { flags.append("deleted") }
        if stored.savedToHealthKit { flags.append("hk") }
        return "[\(raw) \(stored.dose.type) value=\(stored.value) \(stored.dose.startDate)…\(stored.dose.endDate) \(flags.joined(separator: ","))]"
    }
}
