import Foundation

/// Bolus insulin the pump holds on board that the host was never told of: a pump-UI or extended
/// bolus while History Dose Reporting is off, or one whose report was lost.
///
/// One-sided, because the host's IOB is out of the driver's sight and runs on another insulin model.
/// What is left of a bolus never exceeds the bolus, so a pump reading above every bolus reported
/// within the pump's insulin duration means some were never reported.
struct UnreportedInsulinOnBoardMonitor {
    /// Reports are to 0.001 U and the pump's IOB to the milliunit.
    static let tolerance = 0.05
    /// A pump-UI bolus reaches the host only once history reads its completion.
    static let persistence: TimeInterval = .minutes(30)

    enum Finding: Equatable {
        case silent
        case unreported(units: Double)
        case resolved
    }

    /// The excess warned about, until a reading falls back within the boluses reported.
    private(set) var flagged: Double?
    private var excessSince: Date?

    mutating func observe(bolusOnBoard: Double, reported: Double, at now: Date) -> Finding {
        guard bolusOnBoard - reported > Self.tolerance else {
            defer { reset() }
            return flagged == nil ? .silent : .resolved
        }

        let since = excessSince ?? now
        excessSince = since
        guard flagged == nil, now.timeIntervalSince(since) >= Self.persistence else {
            return .silent
        }
        flagged = bolusOnBoard - reported
        return .unreported(units: bolusOnBoard - reported)
    }

    mutating func reset() {
        excessSince = nil
        flagged = nil
    }
}

/// The active profile's insulin duration: how long a bolus stays on the pump's IOB.
public struct PumpInsulinDuration: Equatable {
    public private(set) var current: TimeInterval
    /// A longer duration `current` replaced. Whether the pump moves boluses already given to the
    /// new duration is unknown, so one may stay on board this long after `replacedAt`.
    public private(set) var replaced: TimeInterval?
    public private(set) var replacedAt: Date?

    public init(_ current: TimeInterval, replaced: TimeInterval? = nil, replacedAt: Date? = nil) {
        self.current = current
        self.replaced = replaced
        self.replacedAt = replacedAt
    }

    public func window(at now: Date) -> TimeInterval {
        guard let replaced, let replacedAt, now < replacedAt.addingTimeInterval(replaced) else {
            return current
        }
        return max(current, replaced)
    }

    public mutating func update(to duration: TimeInterval, at date: Date) {
        guard duration != current else {
            return
        }
        let inEffect = window(at: date)
        if duration >= inEffect {
            replaced = nil
            replacedAt = nil
        } else if inEffect == current {
            replaced = current
            replacedAt = date
        }
        current = duration
    }
}

extension PumpInsulinDuration: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let current = rawValue["current"] as? TimeInterval else {
            return nil
        }
        self.init(
            current,
            replaced: rawValue["replaced"] as? TimeInterval,
            replacedAt: (rawValue["replacedAt"] as? TimeInterval).map(Date.init(timeIntervalSinceReferenceDate:))
        )
    }

    public var rawValue: RawValue {
        var raw: RawValue = ["current": current]
        raw["replaced"] = replaced
        raw["replacedAt"] = replacedAt?.timeIntervalSinceReferenceDate
        return raw
    }
}

extension TandemPumpManager {
    func fetchInsulinDuration() {
        guard let status = bluetooth.write(ProfileStatusRequest()) else {
            logger.error("Failed to fetch profile status for the insulin duration")
            return
        }
        guard status.numberOfProfiles > 0 else {
            return
        }
        guard let settings = bluetooth.write(IDPSettingsRequest(idpId: status.activeIdpSlotId)) else {
            logger.error("Failed to fetch the active profile's insulin duration")
            return
        }

        let duration = TimeInterval(settings.insulinDuration) * 60
        guard duration > 0 else {
            logger.warning("Active profile reports no insulin duration")
            return
        }
        if var known = state.pumpInsulinDuration {
            known.update(to: duration, at: now)
            state.pumpInsulinDuration = known
        } else {
            state.pumpInsulinDuration = PumpInsulinDuration(duration)
        }
        notifyDelegateStateUpdated()
    }

    /// Nil when the pump's IOB was not read, or can't be held against the boluses reported.
    @discardableResult
    func fetchInsulinOnBoard() -> UnreportedInsulinOnBoardMonitor.Finding? {
        // A pump with Control-IQ answers IOB under this opcode whether it is on or off. Until one
        // answers a Control-IQ read the opcode is a guess, and a wrong one waits out the 30 s
        // response timeout.
        guard state.controlIQEnabled != nil else {
            return nil
        }
        guard let response = bluetooth.write(ControlIQIOBRequest()) else {
            logger.error("Failed to fetch insulin on board")
            return nil
        }

        let onBoard = Double(response.pumpDisplayedIOB) / 1000
        state.latestInsulinOnBoard = onBoard
        notifyDelegateStateUpdated()

        // Under Control-IQ the pump also counts basal above and below the profile.
        guard response.type == .MUDALIAR,
              let window = state.pumpInsulinDuration?.window(at: now),
              let reported = state.bolusReportLedger.reportedUnits(since: now.addingTimeInterval(-window))
        else {
            logger.debug("Pump IOB: \(Self.formatUnits(onBoard)) (\(String(describing: response.type)))")
            unreportedInsulinOnBoard.reset()
            return nil
        }

        let hours = String(format: "%.1f", window / .hours(1))
        logger.debug(
            "Pump bolus IOB: \(Self.formatUnits(onBoard)); boluses reported in the last \(hours) hours: \(Self.formatUnits(reported))"
        )
        let finding = unreportedInsulinOnBoard.observe(bolusOnBoard: onBoard, reported: reported, at: now)
        switch finding {
        case .silent:
            break
        case let .unreported(units):
            logger.warning(
                "The pump has \(Self.formatUnits(onBoard)) of bolus insulin on board, \(Self.formatUnits(units)) more than "
                    + "all the boluses reported to the app in the last \(hours) hours"
            )
        case .resolved:
            logger.info("Pump bolus IOB is back within the boluses reported to the app")
        }
        return finding
    }

    private static func formatUnits(_ units: Double) -> String {
        String(format: "%.2f U", units)
    }
}
