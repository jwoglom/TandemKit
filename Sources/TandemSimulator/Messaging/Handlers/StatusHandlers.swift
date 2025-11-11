import Foundation
import TandemCore

// MARK: - Home Screen Mirror Handler

class HomeScreenMirrorHandler: MessageHandler {
    var messageType: Message.Type { HomeScreenMirrorRequest.self }

    func handleRequest(
        _ request: Message,
        state: PumpStateProvider,
        context: HandlerContext
    ) throws -> Message {
        // Build response with simulated home screen state
        // Icon IDs are placeholders - actual values would depend on pump state

        // CGM trend icon (0=no data, 1=rapidDown, 2=down, 3=stable, 4=up, 5=rapidUp)
        let cgmTrendIconId: Int
        if state.cgmEnabled, let trend = state.glucoseTrend {
            cgmTrendIconId = trend.rawValue
        } else {
            cgmTrendIconId = 0 // No data
        }

        // CGM alert icon (0=none, other values for various alerts)
        let cgmAlertIconId = 0 // No alert

        // Status icons (0=none, various values for different states)
        let statusIcon0Id = 0 // No status
        let statusIcon1Id = 0 // No status

        // Bolus icon (0=none, 1=active, etc.)
        let bolusStatusIconId = state.activeBolusAmount != nil ? 1 : 0

        // Basal icon (0=none, 1=normal, 2=temp, 3=suspended, etc.)
        let basalStatusIconId = 1 // Normal basal

        // Automation/Control-IQ state (0=off, 1=on, etc.)
        let apControlStateIconId = state.controlIQEnabled ? 1 : 0

        // Remaining insulin indicator
        let remainingInsulinPlusIcon = state.reservoirLevel > 300

        // CGM display data available
        let cgmDisplayData = state.cgmEnabled && state.currentGlucose != nil

        let response = HomeScreenMirrorResponse(
            cgmTrendIconId: cgmTrendIconId,
            cgmAlertIconId: cgmAlertIconId,
            statusIcon0Id: statusIcon0Id,
            statusIcon1Id: statusIcon1Id,
            bolusStatusIconId: bolusStatusIconId,
            basalStatusIconId: basalStatusIconId,
            apControlStateIconId: apControlStateIconId,
            remainingInsulinPlusIcon: remainingInsulinPlusIcon,
            cgmDisplayData: cgmDisplayData
        )

        return response
    }
}

// MARK: - Basal Status Handler

class BasalStatusHandler: MessageHandler {
    var messageType: Message.Type { CurrentBasalStatusRequest.self }

    func handleRequest(
        _ request: Message,
        state: PumpStateProvider,
        context: HandlerContext
    ) throws -> Message {
        // Return current basal delivery status
        var response = CurrentBasalStatusResponse(cargo: Data())

        // Populate with basal state
        // This would include:
        // - Current basal rate
        // - Active profile
        // - Temporary basal (if any)

        return response
    }
}

// MARK: - Bolus Status Handler

class BolusStatusHandler: MessageHandler {
    var messageType: Message.Type { CurrentBolusStatusRequest.self }

    func handleRequest(
        _ request: Message,
        state: PumpStateProvider,
        context: HandlerContext
    ) throws -> Message {
        var response = CurrentBolusStatusResponse(cargo: Data())

        // Populate with bolus state
        // - Active bolus amount and time remaining
        // - Last bolus
        // - IOB (insulin on board)

        return response
    }
}

// MARK: - Time Since Reset Handler

class TimeSinceResetHandler: MessageHandler {
    var messageType: Message.Type { TimeSinceResetRequest.self }

    func handleRequest(
        _ request: Message,
        state: PumpStateProvider,
        context: HandlerContext
    ) throws -> Message {
        // Create response with current time since reset
        let timeSinceReset = state.timeSinceReset

        // Build cargo: 4 bytes little-endian UInt32
        var cargo = Data()
        cargo.append(contentsOf: withUnsafeBytes(of: timeSinceReset.littleEndian) { Data($0) })

        return TimeSinceResetResponse(cargo: cargo)
    }
}

// MARK: - CGM Status Handler

class CGMStatusHandler: MessageHandler {
    var messageType: Message.Type { CGMStatusRequest.self }

    func handleRequest(
        _ request: Message,
        state: PumpStateProvider,
        context: HandlerContext
    ) throws -> Message {
        var response = CGMStatusResponse(cargo: Data())

        // Populate with CGM state if enabled
        // - Current glucose value
        // - Trend
        // - Last reading time
        // - Sensor status

        return response
    }
}

// MARK: - Battery Status Handler

class InsulinStatusHandler: MessageHandler {
    var messageType: Message.Type { InsulinStatusRequest.self }

    func handleRequest(
        _ request: Message,
        state: PumpStateProvider,
        context: HandlerContext
    ) throws -> Message {
        var response = InsulinStatusResponse(cargo: Data())

        // Populate with insulin and battery state
        // - Reservoir level
        // - Battery percentage
        // - Charging status

        return response
    }
}

// MARK: - Reminder Status Handler

class ReminderStatusHandler: MessageHandler {
    var messageType: Message.Type { ReminderStatusRequest.self }

    func handleRequest(
        _ request: Message,
        state: PumpStateProvider,
        context: HandlerContext
    ) throws -> Message {
        var response = ReminderStatusResponse(cargo: Data())

        // Return active reminders

        return response
    }
}

// MARK: - Basal IQ Status Handler

class BasalIQStatusHandler: MessageHandler {
    var messageType: Message.Type { BasalIQStatusRequest.self }

    func handleRequest(
        _ request: Message,
        state: PumpStateProvider,
        context: HandlerContext
    ) throws -> Message {
        var response = BasalIQStatusResponse(cargo: Data())

        // Populate with Basal-IQ state
        // - Enabled/disabled
        // - Currently suspended (if low glucose predicted)
        // - Target glucose

        return response
    }
}

// MARK: - Control IQ Status Handler

class ControlIQStatusHandler: MessageHandler {
    var messageType: Message.Type { ControlIQStatusRequest.self }

    func handleRequest(
        _ request: Message,
        state: PumpStateProvider,
        context: HandlerContext
    ) throws -> Message {
        var response = ControlIQStatusResponse(cargo: Data())

        // Populate with Control-IQ state
        // - Enabled/disabled
        // - Sleep mode
        // - Target range
        // - Current activity

        return response
    }
}

// MARK: - IDP Segment Handler

class IDPSegmentHandler: MessageHandler {
    var messageType: Message.Type { IDPSegmentRequest.self }

    func handleRequest(
        _ request: Message,
        state: PumpStateProvider,
        context: HandlerContext
    ) throws -> Message {
        var response = IDPSegmentResponse(cargo: Data())

        // Return insulin delivery profile segment
        // This defines the basal rates for different times of day

        return response
    }
}
