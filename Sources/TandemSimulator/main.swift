import Foundation
import TandemCore
import TandemBLE

@main
struct TandemSimulatorMain {
    static func main() async {
        do {
            try await runSimulator()
            exit(0)
        } catch let error as SimulatorError {
            if !error.message.isEmpty {
                if error.exitCode == 0 {
                    print(error.message)
                } else {
                    fputs("Error: \(error.message)\n", stderr)
                }
            }
            exit(Int32(error.exitCode))
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private extension TandemSimulatorMain {
    static func runSimulator() async throws {
        let args = CommandLine.arguments
        if args.count < 2 {
            print(usage())
            return
        }

        let command = args[1].lowercased()
        let remainder = Array(args.dropFirst(2))

        switch command {
        case "start":
            let config = try parseStartArguments(remainder)
            try await runStart(config: config)
        case "test":
            let config = try parseTestArguments(remainder)
            try await runTest(config: config)
        case "help", "-h", "--help":
            print(usage())
        default:
            throw SimulatorError("Unknown command: \(command)\n\(usage())", exitCode: 1)
        }
    }

    static func parseStartArguments(_ args: [String]) throws -> SimulatorConfig {
        var config = SimulatorConfig()
        var index = 0

        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--pairing-code":
                index += 1
                guard index < args.count else {
                    throw SimulatorError("Missing value for --pairing-code")
                }
                config.pairingCode = args[index]
            case "--serial":
                index += 1
                guard index < args.count else {
                    throw SimulatorError("Missing value for --serial")
                }
                config.serialNumber = args[index]
            case "--mock-transport":
                config.useMockTransport = true
            case "--help", "-h":
                throw SimulatorError(startUsage(), exitCode: 0)
            default:
                throw SimulatorError("Unknown option: \(arg)\n\(startUsage())")
            }
            index += 1
        }

        return config
    }

    static func parseTestArguments(_ args: [String]) throws -> SimulatorConfig {
        var config = SimulatorConfig()
        config.useMockTransport = true

        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--pairing-code":
                index += 1
                guard index < args.count else {
                    throw SimulatorError("Missing value for --pairing-code")
                }
                config.pairingCode = args[index]
            case "--help", "-h":
                throw SimulatorError(testUsage(), exitCode: 0)
            default:
                throw SimulatorError("Unknown option: \(arg)\n\(testUsage())")
            }
            index += 1
        }

        return config
    }

    static func runStart(config: SimulatorConfig) async throws {
        print("Starting Tandem Pump Simulator")
        print("  Serial: \(config.serialNumber)")
        print("  Transport: \(config.useMockTransport ? "Mock" : "BLE Peripheral")")
        if let code = config.pairingCode {
            print("  Pairing code: \(code)")
        }
        print("")

        let simulator = SimulatedPump(config: config)
        try await simulator.start()

        // Keep running until interrupted
        try await Task.sleep(nanoseconds: UInt64.max)
    }

    static func runTest(config: SimulatorConfig) async throws {
        print("Running simulator in test mode (mock transport)")
        print("  Serial: \(config.serialNumber)")
        if let code = config.pairingCode {
            print("  Pairing code: \(code)")
        }
        print("")

        let simulator = SimulatedPump(config: config)
        try await simulator.start()

        print("Simulator ready for testing")
        print("Use Ctrl-C to stop")

        // Keep running until interrupted
        try await Task.sleep(nanoseconds: UInt64.max)
    }

    static func usage() -> String {
        return [
            "Usage: tandem-simulator <command> [options]",
            "",
            "Commands:",
            "  start    Start the pump simulator",
            "  test     Start in test mode (mock transport, no BLE)",
            "",
            "Use 'tandem-simulator <command> --help' for details on a specific command."
        ].joined(separator: "\n")
    }

    static func startUsage() -> String {
        return [
            "Usage: tandem-simulator start [options]",
            "",
            "Options:",
            "  --pairing-code <code>   Set a pre-defined pairing code",
            "  --serial <number>       Set pump serial number",
            "  --mock-transport        Use mock transport (no BLE)",
        ].joined(separator: "\n")
    }

    static func testUsage() -> String {
        return [
            "Usage: tandem-simulator test [options]",
            "",
            "Options:",
            "  --pairing-code <code>   Set a pre-defined pairing code",
        ].joined(separator: "\n")
    }
}
