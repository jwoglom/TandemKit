import Foundation

// `DispatchTime` is mach_absolute_time, which stops while the device sleeps, so a "30 s" deadline
// on it can run for minutes of real time (#506). Every deadline that bounds a pump command or
// schedules driver work goes through these instead, so none can be written on the uptime clock.

extension DispatchSemaphore {
    func wait(wallTimeout interval: DispatchTimeInterval) -> DispatchTimeoutResult {
        wait(wallTimeout: .now() + interval)
    }
}

extension DispatchQueue {
    func asyncAfter(wallInterval interval: DispatchTimeInterval, execute: DispatchWorkItem) {
        asyncAfter(wallDeadline: .now() + interval, execute: execute)
    }
}
