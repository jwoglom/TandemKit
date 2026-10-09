import Foundation

/// Bolus insulin the pump holds on board that the host was never told of: a pump-UI or extended
/// bolus while History Dose Reporting is off, or one whose report was lost.
///
/// One-sided, because the host's IOB is out of the driver's sight and runs on another insulin model.
/// What is left of a bolus never exceeds the bolus, so a pump reading above every bolus reported
/// within its insulin duration means some were never reported.
struct UnreportedInsulinOnBoardMonitor {
    /// Taken as the longest insulin duration a Tandem profile takes, which is unconfirmed.
    static let window: TimeInterval = .hours(8)
    /// Reports are to 0.001 U and the pump's IOB to the milliunit.
    static let tolerance = 0.05
    /// A pump-UI bolus reaches the host only once history reads its completion.
    static let persistence: TimeInterval = .minutes(30)

    enum Finding: Equatable {
        case silent
        case unreported(units: Double)
        case resolved
    }

    private var excessSince: Date?
    private var hasWarned = false

    mutating func observe(bolusOnBoard: Double, reported: Double, at now: Date) -> Finding {
        guard bolusOnBoard - reported > Self.tolerance else {
            defer { reset() }
            return hasWarned ? .resolved : .silent
        }

        let since = excessSince ?? now
        excessSince = since
        guard !hasWarned, now.timeIntervalSince(since) >= Self.persistence else {
            return .silent
        }
        hasWarned = true
        return .unreported(units: bolusOnBoard - reported)
    }

    mutating func reset() {
        excessSince = nil
        hasWarned = false
    }
}

extension TandemPumpManager {
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
        let since = now.addingTimeInterval(-UnreportedInsulinOnBoardMonitor.window)
        guard response.type == .MUDALIAR, let reported = state.bolusReportLedger.reportedUnits(since: since) else {
            logger.debug("Pump IOB: \(Self.formatUnits(onBoard)) (\(String(describing: response.type)))")
            unreportedInsulinOnBoard.reset()
            return nil
        }

        let hours = Int(UnreportedInsulinOnBoardMonitor.window / .hours(1))
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
