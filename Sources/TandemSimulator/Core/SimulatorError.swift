import Foundation

struct SimulatorError: Error, CustomStringConvertible {
    let message: String
    let exitCode: Int
    var description: String { message }

    init(_ message: String = "", exitCode: Int = 1) {
        self.message = message
        self.exitCode = exitCode
    }
}
