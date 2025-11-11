import Foundation
import Logging

/// Logging utilities for the simulator
enum SimulatorLogging {
    static func setup(level: Logger.Level = .info) {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = level
            return handler
        }
    }
}
