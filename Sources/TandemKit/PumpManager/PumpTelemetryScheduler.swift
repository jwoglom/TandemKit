import Foundation

/// Identifiers for the core telemetry streams we care about.
enum PumpTelemetryKind: CaseIterable {
    case reservoir
    case battery
    case basal
    case bolus
    case timeSinceReset
    case sounds
    case alerts
    case controlIQ
    case homeScreen
    case notifications
    case history

    var logDescription: String {
        switch self {
        case .reservoir:
            return "reservoir"
        case .battery:
            return "battery"
        case .basal:
            return "basal"
        case .bolus:
            return "bolus"
        case .timeSinceReset:
            return "timeSinceReset"
        case .sounds:
            return "Sounds"
        case .alerts:
            return "alerts"
        case .controlIQ:
            return "controlIQ"
        case .homeScreen:
            return "homeScreen"
        case .notifications:
            return "notifications"
        case .history:
            return "history"
        }
    }
}

/// Simple timer-backed scheduler that executes telemetry fetch handlers on a serial queue.
final class PumpTelemetryScheduler {
    private struct Task {
        let timer: DispatchSourceTimer
        let handler: () -> Void
    }

    private let queue: DispatchQueue
    private var tasks: [PumpTelemetryKind: Task] = [:]

    init(label: String) {
        queue = DispatchQueue(label: label)
    }

    /// Schedule a repeating telemetry task.
    func schedule(
        kind: PumpTelemetryKind,
        interval: TimeInterval,
        leeway: TimeInterval = 5.0,
        handler: @escaping () -> Void
    ) {
        queue.sync {
            if let existing = tasks[kind] {
                existing.timer.cancel()
            }

            let timer = DispatchSource.makeTimerSource(queue: queue)
            let leewayNanoseconds = DispatchTimeInterval.milliseconds(Int(leeway * 1000))
            timer.schedule(
                deadline: .now() + interval,
                repeating: interval,
                leeway: leewayNanoseconds
            )
            timer.setEventHandler(handler: handler)
            timer.resume()

            tasks[kind] = Task(timer: timer, handler: handler)
        }
    }

    /// Execute the handler for a specific telemetry kind immediately.
    func trigger(kind: PumpTelemetryKind) {
        queue.async { [weak self] in
            guard let task = self?.tasks[kind] else { return }
            task.handler()
        }
    }

    /// Execute all telemetry handlers immediately.
    func triggerAll() {
        queue.async { [weak self] in
            guard let tasks = self?.tasks.values else { return }
            for task in tasks {
                task.handler()
            }
        }
    }

    /// Cancel the timer for a single telemetry kind, leaving other kinds running.
    func cancel(kind: PumpTelemetryKind) {
        queue.async {
            guard let task = self.tasks.removeValue(forKey: kind) else { return }
            task.timer.cancel()
        }
    }

    /// Cancel all timers.
    func cancelAll() {
        queue.async {
            for task in self.tasks.values {
                task.timer.cancel()
            }
            self.tasks.removeAll()
        }
    }
}
