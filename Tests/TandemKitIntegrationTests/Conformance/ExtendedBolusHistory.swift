import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// faketandem does not deliver extended boluses, so scenarios append the records a pump writes for
/// one, in the order and at the relative times Tandem's cloud export shows: BolusRequestedMsg2,
/// BolusActivated and BolusCompleted for the up-front part, BolexActivated in BolusCompleted's
/// second, BolusDelivery at the start and every five minutes on firmware that writes them, and
/// BolexCompleted at the programmed end or at a stop.
extension ConformanceTestCase {
    /// Waits out the first backfill tick, so anything the pump logs from here on is newer than the
    /// floor it reports from.
    @discardableResult
    func startPairedDriverReportingHistory(scheduledRate: Double = 1.0) throws -> FaketandemHarness.Driver {
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.featureFlags[.historyDoseReporting] = true
        state.bolusReportLedger = BolusReportLedger(trackingSince: clock.now)
        state.insulinType = .novolog
        state.basalRateSchedule = try XCTUnwrap(BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: scheduledRate)]))
        let driver = startDriver(state: state)
        try harness.client.setState(["basal_rate": scheduledRate])
        try harness.pair(driver)
        _ = try sync()
        try IntegrationWait.until("the first backfill tick", timeout: 180) {
            driver.manager.state.historyBackfill != nil
        }
        return driver
    }

    /// The report runs as a command job after the tick; the second sync queues behind it.
    func syncUntilHistoryRead(through sequence: Int, _ driver: FaketandemHarness.Driver) throws {
        _ = try sync()
        try IntegrationWait.until("the backfill to read sequence \(sequence)", timeout: 180) {
            (driver.manager.state.historyBackfill?.watermark).map { Int($0) >= sequence } ?? false
        }
        _ = try sync()
    }

    func extendedPartRaw(bolusId: Int, _ driver: FaketandemHarness.Driver) throws -> Data {
        let serial = try XCTUnwrap(HistoryLogSyncIdentifier.PumpSerial(driver.manager.state.pumpState.pumpSerial))
        return HistoryLogSyncIdentifier.extendedBolus(pumpSerial: serial, bolusId: bolusId)
    }

    func upFrontPartRaw(bolusId: Int, _ driver: FaketandemHarness.Driver) throws -> Data {
        let serial = try XCTUnwrap(HistoryLogSyncIdentifier.PumpSerial(driver.manager.state.pumpState.pumpSerial))
        return HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: bolusId)
    }

    // MARK: - Records

    /// `options` 1 is the t:slim X2's screen, 5 Tandem's Mobi app; `duration` is in minutes.
    func appendExtendedRequest(bolusId: Int, standardPercent: Int, minutes: Int, options: Int = 1) throws {
        try harness.client.appendHistory(type: "BolusRequestedMsg2", secondsAgo: 0, data: [
            "bolusId": bolusId, "options": options, "standardPercent": standardPercent, "duration": minutes,
        ])
    }

    /// `extendedDurationRequested` is in minutes and the running `deliveredTotal` in milliunits.
    func appendExtendedBolusDelivery(
        bolusId: Int,
        upFrontUnits: Double,
        extendedUnits: Double,
        minutes: Int,
        status: BolusDeliveryHistoryLog.BolusDeliveryStatus = .started,
        deliveredUnits: Double = 0
    ) throws {
        let types: [BolusDeliveryHistoryLog.BolusType] = upFrontUnits > 0 ? [.now, .later] : [.later]
        try harness.client.appendHistory(type: "BolusDelivery", secondsAgo: 0, data: [
            "bolusId": bolusId,
            "bolusDeliveryStatus": status.rawValue,
            "bolusTypeBitmask": BolusDeliveryHistoryLog.BolusType.toBitmask(types),
            "bolusSource": BolusDeliveryHistoryLog.BolusSource.gui.rawValue,
            "remoteId": bolusId & 0xFF,
            "requestedNow": Int((upFrontUnits * 1000).rounded()),
            "requestedLater": Int((extendedUnits * 1000).rounded()),
            "extendedDurationRequested": minutes,
            "deliveredTotal": Int((deliveredUnits * 1000).rounded()),
        ])
    }

    func appendBolusActivated(bolusId: Int, units: Double) throws {
        try harness.client.appendHistory(type: "BolusActivated", secondsAgo: 0, data: [
            "bolusId": bolusId, "selectedIob": 0, "iob": 0.0, "bolusSize": units,
        ])
    }

    func appendBolusCompleted(bolusId: Int, units: Double) throws {
        try harness.client.appendHistory(type: "BolusCompleted", secondsAgo: 0, data: [
            "completionStatusId": 3, "bolusId": bolusId, "iob": units, "insulinDelivered": units, "insulinRequested": units,
        ])
    }

    /// Returns its sequence.
    @discardableResult
    func appendBolexActivated(bolusId: Int, units: Double) throws -> Int {
        try harness.client.appendHistory(type: "BolexActivated", secondsAgo: 0, data: [
            "bolusId": bolusId, "selectedIob": 0, "iob": 0.0, "bolexSize": units,
        ]).history.lastSequence
    }

    /// `completionStatus` 3 is completed, 0 stopped by the user, 6 stopped by a Basal-IQ suspend.
    /// Returns its sequence.
    @discardableResult
    func appendBolexCompleted(bolusId: Int, delivered: Double, requested: Double, completionStatus: Int = 3) throws -> Int {
        try harness.client.appendHistory(type: "BolexCompleted", secondsAgo: 0, data: [
            "completionStatus": completionStatus, "bolusId": bolusId, "iob": delivered,
            "insulinDelivered": delivered, "insulinRequested": requested,
        ]).history.lastSequence
    }
}
