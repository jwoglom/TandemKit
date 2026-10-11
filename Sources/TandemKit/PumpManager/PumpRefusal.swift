import Foundation

/// The pump answers a refused command with a status code and no reason, so the reason worded here
/// is only what the driver can read off the command and the pump state it was sent against.
enum PumpRefusal {
    private static let minimumBasalRate = TandemPumpCapabilities.supportedBasalRates.first { $0 > 0 } ?? 0.1

    static func tempBasal(
        _ response: SetTempRateResponse,
        to request: SetTempRateRequest,
        pumpBasalRate: Double,
        maximumTempBasalRate: Double?,
        afterStoppingATemp: Bool
    ) -> PumpCommError {
        let rate = pumpBasalRate * Double(request.percent) / 100
        var sentences = [
            String(
                format: String(
                    localized: "The pump refused the %d%% temporary basal rate (status %d).",
                    comment: "Error when the pump refuses a temp basal; the placeholders are the percent of the pump's basal rate and the pump's status code"
                ),
                request.percent,
                response.status
            )
        ]
        if request.percent > 0, rate < minimumBasalRate - 0.0005 {
            sentences.append(String(
                format: String(
                    localized: "%d%% of its %@ U/hr basal rate is %@ U/hr, below the %@ U/hr the pump can deliver.",
                    comment: "Detail of a refused temp basal: the percent, the pump's basal rate, the rate that percent works out to and the pump's lowest rate"
                ),
                request.percent,
                units(pumpBasalRate),
                units(rate),
                units(minimumBasalRate)
            ))
        } else if let maximumTempBasalRate, rate > maximumTempBasalRate + 0.0005 {
            sentences.append(String(
                format: String(
                    localized: "%d%% of its %@ U/hr basal rate is %@ U/hr, above the pump's maximum basal rate limit of %@ U/hr.",
                    comment: "Detail of a refused temp basal: the percent, the pump's basal rate, the rate that percent works out to and the pump's maximum basal rate limit"
                ),
                request.percent,
                units(pumpBasalRate),
                units(rate),
                units(maximumTempBasalRate)
            ))
        }
        if afterStoppingATemp {
            sentences.append(String(
                localized: "The temporary basal rate that was running had already been stopped, so the pump is back on its scheduled basal rate.",
                comment: "Detail of a refused temp basal when the temp basal it replaces was stopped first"
            ))
        }
        return .errorResponse(context: sentences.joined(separator: " "), request: request, response: response)
    }

    static func stopTempBasal(
        _ response: StopTempRateResponse,
        to request: StopTempRateRequest,
        replacing: Bool
    ) -> PumpCommError {
        let context = replacing
            ? String(
                format: String(
                    localized: "The pump refused to stop the temporary basal rate that is running (status %d), so the new rate was not set. The running one may still be in effect.",
                    comment: "Error when the pump refuses to stop a temp basal to make room for a new one; the placeholder is the pump's status code"
                ),
                response.status
            )
            : String(
                format: String(
                    localized: "The pump refused to cancel the temporary basal rate (status %d). It may still be running.",
                    comment: "Error when the pump refuses to cancel a temp basal; the placeholder is the pump's status code"
                ),
                response.status
            )
        return .errorResponse(context: context, request: request, response: response)
    }

    static func bolusPermission(
        _ response: BolusPermissionResponse,
        to request: BolusPermissionRequest
    ) -> PumpCommError {
        let reason: String
        switch response.nackReason {
        case .invalidPumpingState:
            reason = String(
                localized: "The pump is not in a state that allows a bolus right now, so it did not give permission for the bolus.",
                comment: "Error when the pump refuses a bolus because of its own state"
            )
        case .pumpHasPermission:
            reason = String(
                localized: "The pump already has a bolus request open, possibly from another device or from the pump itself, so it did not give permission for this one.",
                comment: "Error when the pump refuses a bolus because it already holds a bolus request"
            )
        default:
            reason = String(
                format: String(
                    localized: "The pump did not give permission for the bolus (status %d, reason %d).",
                    comment: "Error when the pump refuses a bolus for a reason the app does not know; the placeholders are the pump's status and reason codes"
                ),
                response.status,
                response.nackReasonId
            )
        }
        return .errorResponse(context: reason + " " + bolusNotStarted, request: request, response: response)
    }

    static func initiateBolus(
        _ response: InitiateBolusResponse,
        to request: InitiateBolusRequest
    ) -> PumpCommError {
        let reason: String
        switch response.statusType {
        case .revokedPriority:
            reason = String(
                localized: "The pump revoked permission for the bolus before it started.",
                comment: "Error when the pump takes back its permission for a bolus before starting it"
            )
        default:
            reason = String(
                format: String(
                    localized: "The pump did not start the bolus (status %d, type %d).",
                    comment: "Error when the pump does not start a bolus; the placeholders are the pump's status and type codes"
                ),
                response.status,
                response.statusTypeId
            )
        }
        return .errorResponse(context: reason + " " + bolusNotStarted, request: request, response: response)
    }

    static func cancelBolus(
        _ response: CancelBolusResponse,
        to request: CancelBolusRequest
    ) -> PumpCommError {
        let reason: String
        switch response.reason {
        case .invalidOrAlreadyDelivered:
            reason = String(
                localized: "The pump could not cancel the bolus because it is no longer in progress; it may have already finished.",
                comment: "Error when the pump cannot cancel a bolus that is not running"
            )
        default:
            reason = String(
                format: String(
                    localized: "The pump refused to cancel the bolus (status %d, reason %d). The bolus may still be delivering.",
                    comment: "Error when the pump refuses to cancel a bolus; the placeholders are the pump's status and reason codes"
                ),
                response.statusId,
                response.reasonId
            )
        }
        let check = String(
            localized: "Check the pump to see how much insulin was delivered.",
            comment: "Advice after a bolus could not be canceled"
        )
        return .errorResponse(context: reason + " " + check, request: request, response: response)
    }

    static func maximumBasalLimit(
        _ response: SetMaxBasalLimitResponse,
        to request: SetMaxBasalLimitRequest
    ) -> PumpCommError {
        let context = String(
            format: String(
                localized: "The pump refused the maximum basal rate limit of %@ U/hr (status %d).",
                comment: "Error when the pump refuses a maximum basal rate limit; the placeholders are the limit and the pump's status code"
            ),
            units(Double(request.maxHourlyBasalMilliunits) / 1000),
            response.status
        )
        return .errorResponse(context: context, request: request, response: response)
    }

    static func maximumBolusLimit(
        _ response: SetMaxBolusLimitResponse,
        to request: SetMaxBolusLimitRequest
    ) -> PumpCommError {
        let context = String(
            format: String(
                localized: "The pump refused the maximum bolus limit of %@ U (status %d).",
                comment: "Error when the pump refuses a maximum bolus limit; the placeholders are the limit and the pump's status code"
            ),
            units(Double(request.maxBolusMilliunits) / 1000),
            response.status
        )
        return .errorResponse(context: context, request: request, response: response)
    }

    private static var bolusNotStarted: String {
        String(localized: "No bolus was started.", comment: "Reassurance after the pump refuses to start a bolus")
    }

    /// Three decimals: a rate just under the pump's 0.1 U/hr minimum would read as 0.10 at two.
    private static func units(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
