import Foundation
import LoopKit

/// What TandemKit's temp basal screen shows: the temp rate the pump runs, if any, and its profile.
public struct TempRateStatus: Equatable {
    /// The percent of its profile the pump runs a temp at; nil when it runs none.
    public let percent: Int?
    /// When the temp ends, on the phone's clock; nil when none runs.
    public let endDate: Date?
    public let profileBasalRate: Double
    public let currentBasalRate: Double
    public let isSuspended: Bool
    /// The host's own temp: the driver holds it as set by the host, and it matches the read.
    public let isLoopTemp: Bool
    /// The driver's clock skew compensation temp, which the host is never told of.
    public let isClockSkewCompensation: Bool

    public var isActive: Bool { percent != nil }

    /// A temp set from the screen replaces these two without asking: the user asked for a new temp.
    public var isReplaceable: Bool { isLoopTemp || isClockSkewCompensation }
}

extension TandemPumpManager {
    /// Reads the pump's temp rate and basal status, as the sync does.
    public func readTempRateStatus(completion: @escaping (Result<TempRateStatus, PumpManagerError>) -> Void) {
        let completion = watchdogged(timeoutResult: .failure(.connection(PumpCommError.pumpNotConnected)), completion)

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect to read the temp rate: \(error.localizedDescription)")
                completion(.failure(.connection(PumpCommError.pumpNotConnected)))
                return
            }
            guard let basal = self.processedBasalStatus(), let temp = self.bluetooth.write(TempRateRequest()) else {
                completion(.failure(.communication(PumpCommError.noResponse)))
                return
            }
            completion(.success(self.tempRateStatus(temp, basal)))
        }
    }

    func tempRateStatus(_ temp: TempRateResponse, _ basal: CurrentBasalStatusResponse) -> TempRateStatus {
        guard temp.active else {
            return TempRateStatus(
                percent: nil,
                endDate: nil,
                profileBasalRate: basal.profileBasalRate,
                currentBasalRate: basal.currentBasalRate,
                isSuspended: basal.basalType == .suspend,
                isLoopTemp: false,
                isClockSkewCompensation: false
            )
        }

        // Start and duration are both on the pump's clock, so the end holds however far off that clock is.
        let endDate = temp.startTime.addingTimeInterval(TimeInterval(temp.duration) - state.pumpClockOffset)
        func matches(percent: Int?, end: Date) -> Bool {
            percent == temp.percentage && abs(end.timeIntervalSince(endDate)) <= Self.transitionMatchTolerance
        }
        let held = state.basalDose
        let isHeld = held.type == .tempBasal && matches(percent: held.tempPercent, end: held.estimatedEndDate)
        let isSkewTemp = skewCompensationTemp.map { matches(percent: $0.percent, end: $0.endsAt) } ?? false

        return TempRateStatus(
            percent: temp.percentage,
            endDate: endDate,
            profileBasalRate: basal.profileBasalRate,
            currentBasalRate: basal.currentBasalRate,
            isSuspended: basal.basalType == .suspend,
            isLoopTemp: isHeld && held.setByHost,
            isClockSkewCompensation: isSkewTemp
        )
    }

    /// The non-zero percents the pump takes at every profile rate in force for `duration` from now:
    /// at least its 0.1 U/hr minimum and at most its max basal limit. What it does when a segment
    /// change takes a running temp past either is unconfirmed. Nil when none fits.
    public func manualTempBasalPercents(for duration: TimeInterval, profileBasalRate: Double) -> ClosedRange<Int>? {
        let changes = pumpSegmentChanges(after: now, through: now.addingTimeInterval(duration)).map(\.rate)
        let rates = ([profileBasalRate] + changes).map(TandemPumpCapabilities.milliunits)
        guard rates.allSatisfy({ $0 > 0 }) else { return nil }

        let lowest = rates.map { Self.minimumTempBasalPercent(baseline: Double($0) / 1000) }.max() ?? 1
        var highest = Self.maximumTempBasalPercent
        if let limit = pumpMaximumBasalRate.map(TandemPumpCapabilities.milliunits) {
            highest = rates.reduce(highest) { min($0, limit * 100 / $1) }
        }
        return lowest <= highest ? lowest ... highest : nil
    }

    /// A temp set from TandemKit's settings at `percent` of the pump's profile, reported to the host
    /// as manual so it pauses automatic dosing while the temp runs; at 100% that holds the profile
    /// rate. The number goes out as confirmed or not at all: nothing is clamped or rounded. It
    /// replaces the host's own temp, not another.
    public func enactManualTempBasal(percent: Int, duration: TimeInterval, completion: @escaping (PumpManagerError?) -> Void) {
        let completion = watchdogged(timeoutResult: .connection(PumpCommError.pumpNotConnected), completion)
        logger.info("Setting a manual temp basal at \(percent)% for \(duration)s")

        let isZeroTemp = percent == 0
        let minutes = Int(exactly: duration.minutes.rounded(.down)) ?? Int.max
        if let refusal = tempBasalRefusalBeforeConnecting(.enactManualTempBasal, minutes: minutes, duration: duration, isZeroTemp: isZeroTemp) {
            completion(refusal)
            return
        }
        let programmedDuration = TimeInterval.minutes(Double(minutes))

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for a manual temp basal: \(error.localizedDescription)")
                completion(.connection(PumpCommError.pumpNotConnected))
                return
            }

            if let refusal = self.tempBasalRefusalOnceConnected(.enactManualTempBasal, isCancel: false, isZeroTemp: isZeroTemp) {
                completion(refusal)
                return
            }

            let currentBasal: CurrentBasalStatusResponse
            switch self.readBasalStatusForTempBasal(.enactManualTempBasal, isNonZeroTemp: !isZeroTemp) {
            case let .failure(error):
                completion(error)
                return
            case let .success(status):
                currentBasal = status
            }
            if let refusal = self.tempBasalRefusalWhileSuspended(currentBasal, .enactManualTempBasal) {
                completion(refusal)
                return
            }

            if !isZeroTemp {
                let accepted = self.manualTempBasalPercents(for: programmedDuration, profileBasalRate: currentBasal.profileBasalRate)
                guard accepted?.contains(percent) == true else {
                    self.logger.warning("[enactManualTempBasal] Blocked: \(percent)% is outside \(String(describing: accepted)) over \(minutes) min")
                    completion(.configuration(TandemPumpManagerValidationError.manualTempBasalOutOfRange(percent: percent, accepted: accepted)))
                    return
                }
            }

            guard let temp = self.bluetooth.write(TempRateRequest()) else {
                self.logger.error("Failed to read the running temp rate")
                completion(.communication(PumpCommError.noResponse))
                return
            }
            let running = self.tempRateStatus(temp, currentBasal)
            guard !running.isActive || running.isReplaceable else {
                self.logger.warning("[enactManualTempBasal] Blocked: a \(temp.percentage)% temp rate the host did not set is running")
                completion(.deviceState(TandemPumpManagerValidationError.tempBasalAlreadyRunning))
                return
            }

            let stoppedTemp = running.isLoopTemp ? self.state.basalDose : nil
            if let refusal = self.stopRunningTempBasal(currentBasal, replacing: true) {
                completion(refusal)
                return
            }

            let rate = self.roundToSupportedBasalRate(unitsPerHour: currentBasal.profileBasalRate * Double(percent) / 100)
            let request = SetTempRateRequest(minutes: minutes, percent: percent)
            guard let response = self.bluetooth.write(request) else {
                self.logger.error("Failed to set a manual temp rate")
                let outcome = self.adoptUnansweredTempBasal(rate: rate, percent: percent, duration: programmedDuration, origin: .settings, decisionId: nil)
                if !outcome.adopted, outcome.status?.basalType == .basal {
                    self.restoreStoppedTempBasal(stoppedTemp)
                }
                completion(.communication(PumpCommError.noResponse))
                return
            }

            guard response.isStatusOK else {
                self.logger.error("Failed to set a manual temp rate - Status: \(response.status), percent: \(percent), duration: \(minutes)min")
                self.restoreStoppedTempBasal(stoppedTemp)
                completion(.deviceState(PumpRefusal.tempBasal(
                    response,
                    to: request,
                    pumpBasalRate: currentBasal.profileBasalRate,
                    maximumTempBasalRate: self.state.settings.maxTempBasalRate,
                    afterStoppingATemp: running.isActive,
                    underControlIQ: self.state.useControlIQ
                )))
                return
            }
            self.rememberManualTempRate(tempRateId: response.tempRateId)

            if self.state.useControlIQ {
                // Control-IQ may set the rate the pump runs, but the temp rate it reports is the one it took.
                if let readback = self.bluetooth.write(TempRateRequest()), !(readback.active && readback.percentage == percent) {
                    self.rejectUnconfirmedManualTempBasal(
                        readback,
                        percent: percent,
                        profileBasalRate: currentBasal.profileBasalRate,
                        duration: programmedDuration,
                        tempRateId: response.tempRateId,
                        completion: completion
                    )
                    return
                }
            } else if let readback = self.bluetooth.write(CurrentBasalStatusRequest()) {
                guard Self.tempBasalReadbackMatches(readback, percent: percent) else {
                    self.rejectMismatchedTempBasal(
                        readback,
                        expectedRate: rate,
                        percent: percent,
                        duration: programmedDuration,
                        tempRateId: response.tempRateId,
                        origin: .settings,
                        decisionId: nil,
                        completion: completion
                    )
                    return
                }
            }

            self.recordTempBasal(rate: rate, percent: percent, duration: programmedDuration, tempRateId: response.tempRateId, origin: .settings, decisionId: nil)
            self.logger.info("Manual temp basal enacted at \(percent)% (\(rate) U/hr) for \(minutes) min")
            completion(nil)
        }
    }

    /// Under Control-IQ the pump took the temp but reports another or none. The host is told what the
    /// pump reports, so it counts what goes in, and the set still fails.
    private func rejectUnconfirmedManualTempBasal(
        _ readback: TempRateResponse,
        percent: Int,
        profileBasalRate: Double,
        duration: TimeInterval,
        tempRateId: Int,
        completion: @escaping (PumpManagerError?) -> Void
    ) {
        let running = readback.active ? readback.percentage : nil
        let reported = running.map { "a \($0)%" } ?? "no"
        logger.error("The pump reports \(reported) temp rate after taking a manual temp of \(percent)%")
        if let running {
            let rate = roundToSupportedBasalRate(unitsPerHour: profileBasalRate * Double(running) / 100)
            recordTempBasal(rate: rate, percent: running, duration: duration, tempRateId: tempRateId, origin: .settings, decisionId: nil)
        } else {
            startScheduledBasalDose()
        }
        completion(.deviceState(TandemPumpManagerValidationError.tempRateReadbackMismatch(sent: percent, running: running)))
    }

    /// Stops whatever temp the pump runs, as the host's cancel does but under Control-IQ too: a manual
    /// temp set then can always be stopped from where it was set.
    public func stopTempBasalFromSettings(completion: @escaping (PumpManagerError?) -> Void) {
        let completion = watchdogged(timeoutResult: .connection(PumpCommError.pumpNotConnected), completion)
        logger.info("Stopping the temp basal from settings")
        cancelTempBasal(.stopTempBasalFromSettings, completion: completion)
    }
}
