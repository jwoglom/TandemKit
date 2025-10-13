import Foundation
import TandemCore
import TandemBLE
import TandemKit
#if canImport(Darwin)
import Darwin
#endif
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

@main
struct TandemCLIMain {
    struct DecodeOptions {
        var characteristic: String?
        var format: OutputFormat = .json
        var packets: [String] = []
    }

    struct EncodeOptions {
        var messageName: String = ""
        var txId: UInt8 = 0
        var authKey: String?
        var timeSinceReset: UInt32?
        var maxChunkSize: Int?
        var format: OutputFormat = .json
        var cargo: String?
        var allowInsulinActions: Bool = false
    }

    struct ListOptions {
        var characteristic: String?
        var type: ListKind?
        var format: OutputFormat = .text
    }

    struct PairOptions {
        var pairingCode: String = ""
        var timeout: TimeInterval = 60.0
    }

    struct CredentialOptions {
        var peripheralId: String?
        var derivedSecret: String?
        var serverNonce: String?
        var authKey: String?
    }

    struct SendOptions {
        var messageName: String = ""
        var timeout: TimeInterval = 30.0
        var format: OutputFormat = .text
        var credentials: CredentialOptions = CredentialOptions()
    }

    struct ConsoleOptions {
        var timeout: TimeInterval = 30.0
        var credentials: CredentialOptions = CredentialOptions()
    }

    enum ListKind: String {
        case request
        case response

        var messageType: MessageType {
            switch self {
            case .request:
                return .Request
            case .response:
                return .Response
            }
        }
    }

    static var programName: String {
        (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "tandemkit"
    }

    static func main() async {
        do {
            try await runCLI()
            exit(0)
        } catch let error as CLIError {
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

private extension TandemCLIMain {
    static func runCLI() async throws {
        let args = CommandLine.arguments
        if args.count < 2 {
            throw CLIError(usage(), exitCode: 0)
        }
        let command = args[1].lowercased()
        let remainder = Array(args.dropFirst(2))
        switch command {
        case "decode":
            let options = try parseDecodeArguments(remainder)
            try runDecode(options: options)
        case "encode":
            let options = try parseEncodeArguments(remainder)
            try await runEncode(options: options)
        case "list":
            let options = try parseListArguments(remainder)
            try runList(options: options)
        case "pair":
            let options = try parsePairArguments(remainder)
            try await runPair(options: options)
        case "send":
            let options = try parseSendArguments(remainder)
            try await runSend(options: options)
        case "console":
            let options = try parseConsoleArguments(remainder)
            try await runConsole(options: options)
        case "help", "-h", "--help":
            print(usage())
        default:
            throw CLIError("Unknown command: \(command)\n\(usage())", exitCode: 1)
        }
    }

    static func parseDecodeArguments(_ args: [String]) throws -> DecodeOptions {
        var options = DecodeOptions()
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--characteristic", "-c":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --characteristic.")
                }
                options.characteristic = args[index]
            case "--format", "-f":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --format.")
                }
                guard let format = OutputFormat(rawValue: args[index].lowercased()) else {
                    throw CLIError("Unsupported format: " + args[index] + ". Use json or text.")
                }
                options.format = format
            case "--help", "-h":
                throw CLIError(decodeUsage(), exitCode: 0)
            default:
                if arg.hasPrefix("-") {
                    throw CLIError("Unknown option: \(arg)\n\(decodeUsage())")
                }
                options.packets.append(arg)
            }
            index += 1
        }
        if options.packets.isEmpty {
            throw CLIError("Decode expects at least one packet argument.\n\(decodeUsage())")
        }
        return options
    }

    static func parseEncodeArguments(_ args: [String]) throws -> EncodeOptions {
        var options = EncodeOptions()
        var index = 0
        var messageName: String?
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--txid", "-t":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --txid.")
                }
                guard let value = UInt16(args[index]), value <= 0xFF else {
                    throw CLIError("--txid expects an integer value between 0 and 255.")
                }
                options.txId = UInt8(value)
            case "--auth-key":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --auth-key.")
                }
                options.authKey = args[index]
            case "--time-since-reset":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --time-since-reset.")
                }
                guard let value = UInt32(args[index]) else {
                    throw CLIError("--time-since-reset expects an unsigned integer value.")
                }
                options.timeSinceReset = value
            case "--max-chunk-size":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --max-chunk-size.")
                }
                guard let value = Int(args[index]), value > 0 else {
                    throw CLIError("--max-chunk-size expects a positive integer.")
                }
                options.maxChunkSize = value
            case "--format", "-f":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --format.")
                }
                guard let format = OutputFormat(rawValue: args[index].lowercased()) else {
                    throw CLIError("--format expects json or text.")
                }
                options.format = format
            case "--cargo":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --cargo.")
                }
                options.cargo = args[index]
            case "--allow-insulin-actions":
                options.allowInsulinActions = true
            case "--help", "-h":
                throw CLIError(encodeUsage(), exitCode: 0)
            default:
                if arg.hasPrefix("-") {
                    throw CLIError("Unknown option: \(arg)\n\(encodeUsage())")
                }
                if messageName == nil {
                    messageName = arg
                } else {
                    throw CLIError("Unexpected argument: \(arg)\n\(encodeUsage())")
                }
            }
            index += 1
        }
        guard let name = messageName else {
            throw CLIError("Encode requires a message type name.\n\(encodeUsage())")
        }
        options.messageName = name
        return options
    }

    static func parseSendArguments(_ args: [String]) throws -> SendOptions {
        var options = SendOptions()
        var index = 0
        var messageName: String?
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--timeout", "-t":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --timeout.")
                }
                guard let timeout = TimeInterval(args[index]), timeout > 0 else {
                    throw CLIError("--timeout expects a positive number (seconds).")
                }
                options.timeout = timeout
            case "--format", "-f":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --format.")
                }
                guard let format = OutputFormat(rawValue: args[index].lowercased()) else {
                    throw CLIError("--format expects json or text.")
                }
                options.format = format
            case "--peripheral-id":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --peripheral-id.")
                }
                options.credentials.peripheralId = args[index]
            case "--derived-secret":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --derived-secret.")
                }
                options.credentials.derivedSecret = args[index]
            case "--server-nonce":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --server-nonce.")
                }
                options.credentials.serverNonce = args[index]
            case "--auth-key":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --auth-key.")
                }
                options.credentials.authKey = args[index]
            case "--help", "-h":
                throw CLIError(sendUsage(), exitCode: 0)
            default:
                if arg.hasPrefix("-") {
                    throw CLIError("Unknown option: \(arg)\n\(sendUsage())")
                }
                if messageName == nil {
                    messageName = arg
                } else {
                    throw CLIError("Unexpected argument: \(arg)\n\(sendUsage())")
                }
            }
            index += 1
        }
        guard let name = messageName else {
            throw CLIError("Send requires a message type name.\n\(sendUsage())")
        }
        options.messageName = name
        return options
    }

    static func parseListArguments(_ args: [String]) throws -> ListOptions {
        var options = ListOptions()
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--characteristic", "-c":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --characteristic.")
                }
                options.characteristic = args[index]
            case "--type", "-t":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --type.")
                }
                guard let kind = ListKind(rawValue: args[index].lowercased()) else {
                    throw CLIError("--type expects 'request' or 'response'.")
                }
                options.type = kind
            case "--format", "-f":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --format.")
                }
                guard let format = OutputFormat(rawValue: args[index].lowercased()) else {
                    throw CLIError("--format expects json or text.")
                }
                options.format = format
            case "--help", "-h":
                throw CLIError(listUsage(), exitCode: 0)
            default:
                throw CLIError("Unknown option: \(arg)\n\(listUsage())")
            }
            index += 1
        }
        return options
    }

    static func parsePairArguments(_ args: [String]) throws -> PairOptions {
        var options = PairOptions()
        var index = 0
        var pairingCode: String?
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--timeout", "-t":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --timeout.")
                }
                guard let timeout = TimeInterval(args[index]), timeout > 0 else {
                    throw CLIError("--timeout expects a positive number (seconds).")
                }
                options.timeout = timeout
            case "--help", "-h":
                throw CLIError(pairUsage(), exitCode: 0)
            default:
                if arg.hasPrefix("-") {
                    throw CLIError("Unknown option: \(arg)\n\(pairUsage())")
                }
                if pairingCode == nil {
                    pairingCode = arg
                } else {
                    throw CLIError("Unexpected argument: \(arg)\n\(pairUsage())")
                }
            }
            index += 1
        }
        guard let code = pairingCode else {
            throw CLIError("Pair requires a pairing code.\n\(pairUsage())")
        }
        options.pairingCode = code
        return options
    }

    static func parseConsoleArguments(_ args: [String]) throws -> ConsoleOptions {
        var options = ConsoleOptions()
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--timeout", "-t":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --timeout.")
                }
                guard let timeout = TimeInterval(args[index]), timeout > 0 else {
                    throw CLIError("--timeout expects a positive number (seconds).")
                }
                options.timeout = timeout
            case "--peripheral-id":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --peripheral-id.")
                }
                options.credentials.peripheralId = args[index]
            case "--derived-secret":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --derived-secret.")
                }
                options.credentials.derivedSecret = args[index]
            case "--server-nonce":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --server-nonce.")
                }
                options.credentials.serverNonce = args[index]
            case "--auth-key":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --auth-key.")
                }
                options.credentials.authKey = args[index]
            case "--help", "-h":
                throw CLIError(consoleUsage(), exitCode: 0)
            default:
                throw CLIError("Unknown option: \(arg)\n\(consoleUsage())")
            }
            index += 1
        }
        return options
    }

    static func runDecode(options: DecodeOptions) throws {
        let packetData = try options.packets.map(dataFromHex)
        guard let first = packetData.first else {
            throw CLIError("At least one packet is required to decode a message.")
        }

        let header = try parseHeader(from: first)
        var payload = Data(first.dropFirst(5))
        for extra in packetData.dropFirst() {
            if extra.count < 2 {
                throw CLIError("Additional packets must contain at least 2 bytes (packetsRemaining + txId).")
            }
            payload.append(extra.dropFirst(2))
        }
        if payload.count < 2 {
            throw CLIError("Packet payload is too short to contain CRC bytes.")
        }
        let crc = payload.suffix(2)
        let cargo = Data(payload.dropLast(2))

        let specifiedCharacteristic = try options.characteristic.map { try CharacteristicParser.parse($0) }
        var matches = MessageRegistry.bestMatches(opCode: header.opCode,
                                                  characteristic: specifiedCharacteristic,
                                                  payloadLength: cargo.count)
        if matches.isEmpty {
            matches = MessageRegistry.matches(opCode: header.opCode, characteristic: specifiedCharacteristic)
        }
        if matches.isEmpty {
            let hint = specifiedCharacteristic == nil ? " Provide --characteristic to narrow the search." : ""
            throw CLIError("No message definition matched opcode " + String(header.opCode) + "." + hint)
        }

        let metadata: MessageMetadata
        if matches.count == 1 {
            metadata = matches[0]
        } else {
            if specifiedCharacteristic == nil {
                let options = matches.map { $0.name + " [" + $0.characteristic.rawValue + "]" }.joined(separator: ", ")
                throw CLIError("Multiple messages matched opcode " + String(header.opCode) + ": " + options + ". Provide --characteristic to disambiguate.")
            }
            metadata = matches[0]
        }

        let message = metadata.type.init(cargo: cargo)
        let sanitizedPackets = options.packets.map { sanitizeHexInput($0).lowercased() }
        let output = buildDecodedOutput(metadata: metadata,
                                        message: message,
                                        cargo: cargo,
                                        header: header,
                                        crc: crc,
                                        packets: sanitizedPackets)

        switch options.format {
        case .json:
            try printJSON(output)
        case .text:
            printDecodedText(output: output, message: message)
        }
    }

    @MainActor
    static func runEncode(options: EncodeOptions) throws {
        guard let metadata = MessageRegistry.metadata(forName: options.messageName) else {
            throw CLIError("Unknown message type " + options.messageName + ". Use '" + programName + " list' to view available names.")
        }

        let cargoData: Data
        if let cargo = options.cargo {
            cargoData = try dataFromHex(cargo)
        } else if metadata.size == 0 && !metadata.variableSize {
            cargoData = Data()
        } else {
            throw CLIError("Message " + metadata.name + " expects payload bytes. Provide --cargo <hex>.")
        }

        let message = metadata.type.init(cargo: cargoData)

        if metadata.modifiesInsulinDelivery {
            if !options.allowInsulinActions {
                throw CLIError("Message " + metadata.name + " modifies insulin delivery. Pass --allow-insulin-actions to proceed.")
            }
            PumpStateSupplier.enableActionsAffectingInsulinDelivery()
        }

        var authKeyData: Data?
        if let authKey = options.authKey {
            authKeyData = try dataFromHex(authKey)
        }
        var tsr: UInt32?
        if metadata.signed {
            guard let key = authKeyData else {
                throw CLIError("Message " + metadata.name + " is signed. Provide --auth-key <hex>.")
            }
            guard let time = options.timeSinceReset else {
                throw CLIError("Message " + metadata.name + " is signed. Provide --time-since-reset <seconds>.")
            }
            authKeyData = key
            tsr = time
        }

        do {
            let packets = try Packetize(message: message,
                                        authenticationKey: authKeyData,
                                        txId: options.txId,
                                        timeSinceReset: tsr,
                                        maxChunkSize: options.maxChunkSize)
            let merged = packets.reduce(into: Data()) { $0.append($1.build) }
            let output = buildEncodedOutput(metadata: metadata,
                                             message: message,
                                             cargo: cargoData,
                                             packets: packets,
                                             merged: merged)
            switch options.format {
            case .json:
                try printJSON(output)
            case .text:
                printEncodedText(output: output, message: message)
            }
        } catch is ActionsAffectingInsulinDeliveryNotEnabled {
            throw CLIError("Encoding aborted: actions affecting insulin delivery are disabled. Pass --allow-insulin-actions to override.")
        } catch PacketizeError.missingAuthenticationKey {
            throw CLIError("Authentication key and time since reset are required for signed messages.")
        }
    }

    static func runList(options: ListOptions) throws {
        let specifiedCharacteristic = try options.characteristic.map { try CharacteristicParser.parse($0) }
        var items = MessageRegistry.all
        if let characteristic = specifiedCharacteristic {
            items = items.filter { $0.characteristic == characteristic }
        }
        if let kind = options.type?.messageType {
            items = items.filter { $0.messageType == kind }
        }

        switch options.format {
        case .json:
            let summaries = items.map { metadata -> [String: AnyEncodable] in
                [
                    "name": AnyEncodable(metadata.name),
                    "type": AnyEncodable(String(describing: metadata.messageType)),
                    "characteristic": AnyEncodable(metadata.characteristic.rawValue),
                    "opCode": AnyEncodable(metadata.opCode),
                    "expectedCargoSize": AnyEncodable(metadata.size),
                    "signed": AnyEncodable(metadata.signed),
                    "variableSize": AnyEncodable(metadata.variableSize),
                    "stream": AnyEncodable(metadata.stream),
                    "modifiesInsulinDelivery": AnyEncodable(metadata.modifiesInsulinDelivery)
                ]
            }
            try printJSON(summaries)
        case .text:
            for metadata in items.sorted(by: { $0.name < $1.name }) {
                let kind = String(describing: metadata.messageType)
                let opHex = String(format: "0x%02X", metadata.opCode)
                let line = metadata.name + " [" + kind + "] op: " + String(metadata.opCode) + " (" + opHex + ") characteristic: " + metadata.characteristic.rawValue
                print(line)
            }
        }
    }

    static func usage() -> String {
        return [
            "Usage: " + programName + " <command> [options]",
            "",
            "Commands:",
            "  decode   Decode a message from hex packets.",
            "  encode   Encode a message into BLE packets.",
            "  list     List available message definitions.",
            "  pair     Pair with a Tandem pump via Bluetooth.",
            "  send     Send a message to a paired pump and display the response.",
            "  console  Interactive console with persistent pump connection.",
            "",
            "Use '" + programName + " <command> --help' for details on a specific command."
        ].joined(separator: "\n")
    }

    static func decodeUsage() -> String {
        return [
            "Usage: " + programName + " decode [options] <packet> [extra packets...]",
            "",
            "Options:",
            "  -c, --characteristic <value>  Bluetooth characteristic alias or UUID.",
            "  -f, --format <json|text>      Output formatting (default: json)."
        ].joined(separator: "\n")
    }

    static func encodeUsage() -> String {
        return [
            "Usage: " + programName + " encode [options] <MessageName>",
            "",
            "Options:",
            "  -t, --txid <value>            Transaction identifier (0-255). Default: 0.",
            "      --auth-key <hex>          Authentication key for signed messages.",
            "      --time-since-reset <sec>  Pump time since reset for signed messages.",
            "      --max-chunk-size <n>      Override packet chunk size.",
            "  -f, --format <json|text>      Output formatting (default: json).",
            "      --cargo <hex>             Message cargo as hexadecimal.",
            "      --allow-insulin-actions   Permit encoding of insulin-delivery commands."
        ].joined(separator: "\n")
    }

    static func listUsage() -> String {
        return [
            "Usage: " + programName + " list [options]",
            "",
            "Options:",
            "  -c, --characteristic <value>  Filter by characteristic.",
            "  -t, --type <request|response> Filter by message direction.",
            "  -f, --format <json|text>      Output formatting (default: text)."
        ].joined(separator: "\n")
    }

    static func pairUsage() -> String {
        return [
            "Usage: " + programName + " pair [options] <pairing-code>",
            "",
            "Options:",
            "  -t, --timeout <seconds>  Connection timeout (default: 60).",
            "",
            "Pairing Code:",
            "  6-digit code (e.g., 123456) for JPAKE authentication",
            "  16-character code (e.g., abcd-efgh-ijkl-mnop) for legacy authentication"
        ].joined(separator: "\n")
    }

    static func sendUsage() -> String {
        return [
            "Usage: " + programName + " send [options] <MessageName>",
            "",
            "Options:",
            "  -t, --timeout <seconds>       Connection timeout (default: 30).",
            "  -f, --format <json|text>      Output formatting (default: text).",
            "      --peripheral-id <uuid>    Peripheral UUID from previous pairing.",
            "      --derived-secret <hex>    Derived secret from pairing.",
            "      --server-nonce <hex>      Server nonce from pairing.",
            "      --auth-key <hex>          Authentication key from pairing.",
            "",
            "Description:",
            "  Sends a request message to a paired pump and displays the response.",
            "  Only works with messages that require no parameters (e.g., HomeScreenMirrorRequest).",
            "",
            "  If you provide pairing credentials (derived-secret, server-nonce, auth-key),",
            "  they will be used instead of looking for previously stored credentials.",
            "  You can obtain these from the output of the 'pair' command."
        ].joined(separator: "\n")
    }

    static func consoleUsage() -> String {
        return [
            "Usage: " + programName + " console [options]",
            "",
            "Options:",
            "  -t, --timeout <seconds>       Connection timeout (default: 30).",
            "      --peripheral-id <uuid>    Peripheral UUID from previous pairing.",
            "      --derived-secret <hex>    Derived secret from pairing.",
            "      --server-nonce <hex>      Server nonce from pairing.",
            "      --auth-key <hex>          Authentication key from pairing.",
            "",
            "Description:",
            "  Opens an interactive console with a persistent pump connection.",
            "  Use Ctrl-C to exit the console.",
            "",
            "  Console Commands:",
            "    send <MessageName>  Send a parameter-less request message",
            "    help                Show available commands",
            "    exit                Exit the console",
            "",
            "  If you provide pairing credentials (derived-secret, server-nonce, auth-key),",
            "  they will be used instead of looking for previously stored credentials.",
            "  You can obtain these from the output of the 'pair' command."
        ].joined(separator: "\n")
    }

    static func runPair(options: PairOptions) async throws {
        #if canImport(CoreBluetooth) && !os(Linux)
        guard !options.pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIError("Pairing code cannot be empty.")
        }

        let sanitizedCode = try await MainActor.run {
            try PumpStateSupplier.sanitizeAndStorePairingCode(options.pairingCode)
        }

        let codeLength = sanitizedCode.count
        let pairingMode = codeLength == 6 ? "JPAKE (6-digit)" : "Legacy (16-character)"

        print("Starting Tandem pump pairing")
        print("  Pairing code: \(sanitizedCode)")
        print("  Mode: \(pairingMode)")
        print("  Timeout: \(String(format: "%.0f", options.timeout)) seconds")
        print("")
        print("Searching for nearby Tandem pumps...")

        let coordinator = PairingCoordinator(pairingCode: sanitizedCode, timeout: options.timeout)
        let result: PairingResult

        do {
            result = try await coordinator.start()
        } catch {
            throw CLIError("Pairing failed: \(String(describing: error))")
        }

        let derivedSecretHex = result.pumpState.derivedSecret?.hexadecimalString ?? "<not provided>"
        let serverNonceHex = result.pumpState.serverNonce?.hexadecimalString ?? "<not provided>"
        let authKeyHex = await MainActor.run { PumpStateSupplier.authenticationKey().hexadecimalString }

        print("")
        print("✅ Pairing completed successfully")
        if let name = result.peripheralName {
            print("  Pump name: \(name)")
        }
        if let identifier = result.peripheralIdentifier {
            print("  Peripheral ID: \(identifier.uuidString)")
        }
        print("  Derived secret: \(derivedSecretHex)")
        print("  Server nonce: \(serverNonceHex)")
        print("  Authentication key: \(authKeyHex)")

        print("")
        #else
        throw CLIError("Pairing command is only available on platforms with CoreBluetooth support.")
        #endif
    }

    static func runSend(options: SendOptions) async throws {
        #if canImport(CoreBluetooth) && !os(Linux)
        // Validate message name
        guard let metadata = MessageRegistry.metadata(forName: options.messageName) else {
            throw CLIError("Unknown message type '\(options.messageName)'. Use '\(programName) list' to view available names.")
        }

        // Only allow Request messages
        guard metadata.messageType == .Request else {
            throw CLIError("'\(options.messageName)' is a response message. Only request messages can be sent.")
        }

        // Setup credentials using helper
        try setupCredentials(options.credentials)

        // Instantiate the message with empty cargo
        let cargoData: Data
        if metadata.size == 0 && !metadata.variableSize {
            cargoData = Data()
        } else {
            throw CLIError("Message '\(metadata.name)' requires parameters. The send command only supports parameter-less messages.")
        }

        let message = metadata.type.init(cargo: cargoData)

        print("Sending message to paired pump")
        print("  Message: \(metadata.name)")
        print("  OpCode: \(metadata.opCode)")
        print("  Characteristic: \(metadata.characteristic.rawValue)")
        print("  Timeout: \(String(format: "%.0f", options.timeout)) seconds")
        print("")
        print("Searching for pump...")

        let coordinator = SendCoordinator(message: message, metadata: metadata, timeout: options.timeout)
        let result: SendResult

        do {
            result = try await coordinator.start()
        } catch {
            throw CLIError("Send failed: \(String(describing: error))")
        }

        print("")
        print("✅ Message sent and response received")
        print("")

        // Display the response
        switch options.format {
        case .text:
            print("Request:")
            print("  Type: \(metadata.name)")
            print("  OpCode: \(metadata.opCode)")
            print("")
            print("Response:")
            let responseTypeName = String(describing: type(of: result.response))
            print("  Type: \(responseTypeName)")
            if let responseMeta = MessageRegistry.metadata(for: result.response) {
                print("  OpCode: \(responseMeta.opCode)")
                print("  Size: \(responseMeta.size) bytes")
            }
            let fields = messagePropertyDescriptions(result.response)
            if !fields.isEmpty {
                print("  Fields:")
                for key in fields.keys.sorted() {
                    if let value = fields[key] {
                        print("    \(key): \(value)")
                    }
                }
            }
        case .json:
            let requestInfo: [String: AnyEncodable] = [
                "type": AnyEncodable(metadata.name),
                "opCode": AnyEncodable(metadata.opCode),
                "characteristic": AnyEncodable(metadata.characteristic.rawValue)
            ]

            var responseInfo: [String: AnyEncodable] = [
                "type": AnyEncodable(String(describing: type(of: result.response)))
            ]
            if let responseMeta = MessageRegistry.metadata(for: result.response) {
                responseInfo["opCode"] = AnyEncodable(responseMeta.opCode)
                responseInfo["size"] = AnyEncodable(responseMeta.size)
            }

            let fields = messagePropertyDescriptions(result.response)
            if !fields.isEmpty {
                responseInfo["fields"] = AnyEncodable(fields)
            }

            let output: [String: AnyEncodable] = [
                "request": AnyEncodable(requestInfo),
                "response": AnyEncodable(responseInfo)
            ]
            try printJSON(output)
        }

        #else
        throw CLIError("Send command is only available on platforms with CoreBluetooth support.")
        #endif
    }

    static func setupCredentials(_ credentials: CredentialOptions) throws {
        // If credentials are provided, set them up
        if let derivedSecretHex = credentials.derivedSecret,
           let serverNonceHex = credentials.serverNonce,
           let authKeyHex = credentials.authKey {

            // Parse hex strings
            let derivedSecret = try dataFromHex(derivedSecretHex)
            let serverNonce = try dataFromHex(serverNonceHex)
            let _ = try dataFromHex(authKeyHex)  // Validate authKey format but don't use it directly

            // Store in PumpStateSupplier
            PumpStateSupplier.storePairingArtifacts(derivedSecret: derivedSecret, serverNonce: serverNonce)

            print("Using provided pairing credentials")
            print("  Derived secret: \(derivedSecret.hexadecimalString.prefix(16))...")
            print("  Server nonce: \(serverNonce.hexadecimalString.prefix(16))...")
            if let peripheralId = credentials.peripheralId {
                print("  Target peripheral: \(peripheralId)")
            }
        } else if credentials.derivedSecret != nil || credentials.serverNonce != nil || credentials.authKey != nil {
            // Partial credentials provided
            throw CLIError("If providing credentials, you must specify all three: --derived-secret, --server-nonce, and --auth-key.")
        } else {
            // Check if authentication is available from previous pairing
            let authKey = PumpStateSupplier.authenticationKey()
            if authKey.isEmpty {
                throw CLIError("No pairing credentials found. Either:\n  1. Pair first using '\(programName) pair <code>', or\n  2. Provide credentials with --derived-secret, --server-nonce, and --auth-key.")
            }
            print("Using previously stored pairing credentials")
        }
    }

    static func runConsole(options: ConsoleOptions) async throws {
        #if canImport(CoreBluetooth) && !os(Linux)
        // Setup credentials
        try setupCredentials(options.credentials)

        print("Starting interactive console")
        print("  Timeout: \(String(format: "%.0f", options.timeout)) seconds")
        print("")
        print("Searching for pump...")

        let coordinator = ConsoleCoordinator(timeout: options.timeout)
        try await coordinator.start()

        #else
        throw CLIError("Console command is only available on platforms with CoreBluetooth support.")
        #endif
    }

    static func printDecodedText(output: DecodedMessageOutput, message: Message) {
        let typeDescription = String(describing: output.message.type)
        let headerTx = String(output.header.packetTxId)
        let messageTx = String(output.header.messageTxId)
        let declaredSize = String(output.header.declaredPayloadSize)
        let actualSize = String(output.header.actualPayloadSize)
        print("Message: " + output.message.name + " [" + typeDescription + "]")
        print("Characteristic: " + output.message.characteristicUUID)
        let opcodeHex = String(format: "0x%02X", output.message.opCode)
        print("Opcode: " + String(output.message.opCode) + " (" + opcodeHex + ")")
        print("Packet txId: " + headerTx + "  Message txId: " + messageTx)
        print("Declared payload size: " + declaredSize + " bytes")
        print("Actual payload size: " + actualSize + " bytes")
        print("CRC: " + output.header.crc)
        print("Cargo: " + output.message.cargo)
        let fields = messagePropertyDescriptions(message)
        if !fields.isEmpty {
            print("Fields:")
            for key in fields.keys.sorted() {
                if let value = fields[key] {
                    print("  " + key + ": " + value)
                }
            }
        }
        if !output.packets.isEmpty {
            print("Packets:")
            for (index, hex) in output.packets.enumerated() {
                print("  [" + String(index) + "] " + hex)
            }
        }
    }

    static func printEncodedText(output: EncodedMessageOutput, message: Message) {
        let typeDescription = String(describing: output.message.type)
        print("Message: " + output.message.name + " [" + typeDescription + "]")
        print("Characteristic: " + output.message.characteristicUUID)
        let opcodeHex = String(format: "0x%02X", output.message.opCode)
        print("Opcode: " + String(output.message.opCode) + " (" + opcodeHex + ")")
        print("Cargo: " + output.message.cargo)
        let fields = messagePropertyDescriptions(message)
        if !fields.isEmpty {
            print("Fields:")
            for key in fields.keys.sorted() {
                if let value = fields[key] {
                    print("  " + key + ": " + value)
                }
            }
        }
        print("Packets:")
        for packet in output.packets {
            print("  [" + String(packet.index) + "] remaining=" + String(packet.packetsRemaining) + " txId=" + String(packet.txId) + " hex=" + packet.hex)
        }
        print("Merged: " + output.mergedHex)
    }
}

#if canImport(CoreBluetooth) && !os(Linux)
import CoreBluetooth

private struct PairingResult {
    let pumpState: PumpState
    let peripheralName: String?
    let peripheralIdentifier: UUID?
}

private struct SendResult {
    let response: Message
    let peripheralName: String?
    let peripheralIdentifier: UUID?
}

private final class PairingCoordinator: NSObject, BluetoothManagerDelegate, PumpCommDelegate {
    private let pairingCode: String
    private let timeout: TimeInterval
    private let bluetoothManager = BluetoothManager()
    private let pumpComm: PumpComm
    private var transport: PeripheralManagerTransport?
    private var eventListenerTask: Task<Void, Never>?

    private var continuation: CheckedContinuation<PairingResult, Error>?
    private let stateQueue = DispatchQueue(label: "com.jwoglom.TandemCLI.PairingCoordinator.state")
    private var timeoutWorkItem: DispatchWorkItem?
    private var lastPumpState: PumpState = PumpState()
    private var targetPeripheral: CBPeripheral?
    private var didStartPairing = false

    init(pairingCode: String, timeout: TimeInterval) {
        self.pairingCode = pairingCode
        self.timeout = timeout
        self.pumpComm = PumpComm(pumpState: nil)
        super.init()

        bluetoothManager.delegate = self
        pumpComm.delegate = self
    }

    deinit {
        bluetoothManager.delegate = nil
        eventListenerTask?.cancel()
        pumpComm.delegate = nil
    }

    func start() async throws -> PairingResult {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.sync { self.continuation = continuation }
            scheduleTimeout()
            DispatchQueue.main.async {
                self.bluetoothManager.scanForPeripheral()
            }
        }
    }

    // MARK: - BluetoothManagerDelegate

    func bluetoothManager(_ manager: BluetoothManager,
                          shouldConnectPeripheral peripheral: CBPeripheral,
                          advertisementData: [String : Any]?) -> Bool {
        return stateQueue.sync {
            if let target = targetPeripheral, target.identifier != peripheral.identifier {
                return false
            }
            if targetPeripheral == nil {
                targetPeripheral = peripheral
                print("Discovered pump candidate: \(peripheral.name ?? peripheral.identifier.uuidString)")
            }
            return true
        }
    }

    func bluetoothManager(_ manager: BluetoothManager,
                          peripheralManager: PeripheralManager,
                          isReadyWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else {
            print("Connected. Waiting for configuration...")
        }
    }

    func bluetoothManager(_ manager: BluetoothManager,
                          didCompleteConfiguration peripheralManager: PeripheralManager) {
        let shouldStartPairing: Bool = stateQueue.sync {
            if didStartPairing {
                return false
            }
            didStartPairing = true
            transport = PeripheralManagerTransport(peripheralManager: peripheralManager)
            return true
        }

        guard shouldStartPairing, let transport else { return }

        print("Peripheral configured. Beginning pairing exchange...")

        // Run JPAKE initialization and pairing on background queue to avoid blocking
        Task.detached { [weak self] in
            guard let self else { return }
            do {
#if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
                if self.pairingCode.count == 6 {
                    print("[PairingCoordinator] priming JPAKE handshake (background)")
                    let builder = JpakeAuthBuilder.initializeWithPairingCode(self.pairingCode)
                    if let initialRequest = builder.nextRequest() {
                    print("[PairingCoordinator] sending initial JPAKE request: \(initialRequest)")
                        do {
                            let initialResponse = try self.pumpComm.sendMessage(transport: transport, message: initialRequest)
                            print("[PairingCoordinator] received initial response: \(initialResponse)")
                            builder.processResponse(initialResponse)
                        } catch {
                            print("[PairingCoordinator] initial JPAKE exchange failed: \(error)")
                            self.finish(.failure(error))
                            return
                        }
                    } else {
                        print("[PairingCoordinator] initial JPAKE request unavailable")
                    }
                }
#endif

                print("[PairingCoordinator] invoking PumpComm.pair")
                try self.pumpComm.pair(transport: transport, pairingCode: self.pairingCode)
                let state = self.stateQueue.sync { self.lastPumpState }
                self.finish(.success(PairingResult(pumpState: state,
                                                   peripheralName: self.targetPeripheral?.name,
                                                   peripheralIdentifier: self.targetPeripheral?.identifier)))
            } catch {
                print("[PairingCoordinator] PumpComm.pair failed: \(error)")
                self.finish(.failure(CLIError(String(describing: error))))
            }
        }
    }

    func bluetoothManager(_ manager: BluetoothManager,
                          didIdentifyPump manufacturer: String,
                          model: String) {
        print("[PairingCoordinator] pump model identified manufacturer=\(manufacturer) model=\(model)")
    }

    // MARK: - PumpCommDelegate

    func pumpComm(_ pumpComms: PumpComm, didChange pumpState: PumpState) {
        stateQueue.sync {
            self.lastPumpState = pumpState
        }

        let derivedHex = pumpState.derivedSecret?.hexadecimalString ?? "none"
        let nonceHex = pumpState.serverNonce?.hexadecimalString ?? "none"
        print("Pump state updated (derivedSecret: \(derivedHex.prefix(8))…, serverNonce: \(nonceHex.prefix(8))…)")
    }

    // MARK: - Helpers

    private func scheduleTimeout() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finish(.failure(CLIError("Pairing timed out after \(Int(self.timeout)) seconds.")))
        }
        timeoutWorkItem = workItem
        print("[PairingCoordinator] scheduling timeout in \(Int(timeout)) seconds")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + self.timeout, execute: workItem)
    }

    private func cancelTimeout() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
    }

    private func finish(_ result: Result<PairingResult, Error>) {
        let continuation: CheckedContinuation<PairingResult, Error>? = stateQueue.sync {
            defer { self.continuation = nil }
            return self.continuation
        }

        guard let continuation else { return }

        cancelTimeout()

        DispatchQueue.main.async {
            print("[PairingCoordinator] Disconnecting peripheral")
            self.bluetoothManager.permanentDisconnect()
        }

        switch result {
        case .success(let value):
            print("[PairingCoordinator] Completing with success")
            let derivedHex = value.pumpState.derivedSecret?.hexadecimalString ?? "none"
            let nonceHex = value.pumpState.serverNonce?.hexadecimalString ?? "none"
            print("[PairingCoordinator] PumpState derivedSecret=\(derivedHex) serverNonce=\(nonceHex)")
            continuation.resume(returning: value)
        case .failure(let error):
            print("[PairingCoordinator] Completing with failure: \(error)")
            continuation.resume(throwing: error)
        }
    }
}

private final class SendCoordinator: NSObject, BluetoothManagerDelegate {
    private let message: Message
    private let metadata: MessageMetadata
    private let timeout: TimeInterval
    private let bluetoothManager = BluetoothManager()
    private var transport: PeripheralManagerTransport?

    private var continuation: CheckedContinuation<SendResult, Error>?
    private let stateQueue = DispatchQueue(label: "com.jwoglom.TandemCLI.SendCoordinator.state")
    private var timeoutWorkItem: DispatchWorkItem?
    private var targetPeripheral: CBPeripheral?
    private var didSendMessage = false

    init(message: Message, metadata: MessageMetadata, timeout: TimeInterval) {
        self.message = message
        self.metadata = metadata
        self.timeout = timeout
        super.init()
        bluetoothManager.delegate = self
    }

    deinit {
        bluetoothManager.delegate = nil
    }

    func start() async throws -> SendResult {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.sync { self.continuation = continuation }
            scheduleTimeout()
            DispatchQueue.main.async {
                self.bluetoothManager.scanForPeripheral()
            }
        }
    }

    // MARK: - BluetoothManagerDelegate

    func bluetoothManager(_ manager: BluetoothManager,
                          shouldConnectPeripheral peripheral: CBPeripheral,
                          advertisementData: [String : Any]?) -> Bool {
        return stateQueue.sync {
            if let target = targetPeripheral, target.identifier != peripheral.identifier {
                return false
            }
            if targetPeripheral == nil {
                targetPeripheral = peripheral
                print("Discovered pump: \(peripheral.name ?? peripheral.identifier.uuidString)")
            }
            return true
        }
    }

    func bluetoothManager(_ manager: BluetoothManager,
                          peripheralManager: PeripheralManager,
                          isReadyWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else {
            print("Connected. Waiting for configuration...")
        }
    }

    func bluetoothManager(_ manager: BluetoothManager,
                          didCompleteConfiguration peripheralManager: PeripheralManager) {
        let shouldSend: Bool = stateQueue.sync {
            if didSendMessage {
                return false
            }
            didSendMessage = true
            transport = PeripheralManagerTransport(peripheralManager: peripheralManager)
            return true
        }

        guard shouldSend, let transport else { return }

        print("Peripheral configured.")

        // Send message on background queue
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                // Check if we need to perform quick JPAKE confirmation
                #if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
                if let derivedSecretData = PumpStateSupplier.getDerivedSecret() {
                    print("[SendCoordinator] Performing quick JPAKE confirmation with existing credentials...")

                    // Use dummy pairing code - it's not needed for CONFIRM_INITIAL mode
                    let builder = JpakeAuthBuilder.initializeWithDerivedSecret(pairingCode: "000000", derivedSecret: derivedSecretData)

                    // Run the quick JPAKE confirmation flow (Jpake3 + Jpake4)
                    while let request = builder.nextRequest(), !builder.done() && !builder.invalid() {
                        print("[SendCoordinator] Sending JPAKE request: \(type(of: request))")
                        let response = try transport.sendMessage(request)
                        print("[SendCoordinator] Received JPAKE response: \(type(of: response))")
                        builder.processResponse(response)
                    }

                    if builder.invalid() {
                        throw CLIError("JPAKE confirmation failed - invalid credentials")
                    }

                    if builder.done() {
                        print("[SendCoordinator] Quick JPAKE confirmation completed successfully")
                    }
                }
                #endif

                // Now send the actual message
                print("Sending message...")
                let response = try transport.sendMessage(self.message)
                print("Received response: \(String(describing: type(of: response)))")
                self.finish(.success(SendResult(response: response,
                                                peripheralName: self.targetPeripheral?.name,
                                                peripheralIdentifier: self.targetPeripheral?.identifier)))
            } catch {
                print("Send message failed: \(error)")
                self.finish(.failure(CLIError(String(describing: error))))
            }
        }
    }

    func bluetoothManager(_ manager: BluetoothManager,
                          didIdentifyPump manufacturer: String,
                          model: String) {
        print("Pump model identified: \(manufacturer) \(model)")
    }

    // MARK: - Helpers

    private func scheduleTimeout() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finish(.failure(CLIError("Send timed out after \(Int(self.timeout)) seconds.")))
        }
        timeoutWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + self.timeout, execute: workItem)
    }

    private func cancelTimeout() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
    }

    private func finish(_ result: Result<SendResult, Error>) {
        let continuation: CheckedContinuation<SendResult, Error>? = stateQueue.sync {
            defer { self.continuation = nil }
            return self.continuation
        }

        guard let continuation else { return }

        cancelTimeout()

        DispatchQueue.main.async {
            self.bluetoothManager.permanentDisconnect()
        }

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private final class ConsoleCoordinator: NSObject, BluetoothManagerDelegate {
    private static let supportedCommands = ["send", "list", "help", "exit", "quit"]
    private static let sendableMessageNames: [String] = {
        MessageRegistry.all
            .filter { $0.messageType == .Request && $0.size == 0 }
            .map { $0.name }
            .sorted()
    }()
    private static weak var activeCoordinator: ConsoleCoordinator?
    private static var signalHandlerInstalled = false
    private static let sigintHandler: @convention(c) (Int32) -> Void = { signal in
        ConsoleLineEditor.handleInterruptSignal()
        ConsoleCoordinator.activeCoordinator?.handleInterruptAndExit()
        exit(signal)
    }

    private let timeout: TimeInterval
    private let bluetoothManager = BluetoothManager()
    private var transport: PeripheralManagerTransport?
    private let lineEditor: ConsoleLineEditor
    private var eventListenerTask: Task<Void, Never>?
    private var previousLogHandler: PumpLogging.Handler?
    private let logger = PumpLogger(label: "TandemCLI.Console")

    private var continuation: CheckedContinuation<Void, Error>?
    private let stateQueue = DispatchQueue(label: "com.jwoglom.TandemCLI.ConsoleCoordinator.state")
    private var timeoutWorkItem: DispatchWorkItem?
    private var targetPeripheral: CBPeripheral?
    private var didStartConsole = false
    private var shouldExit = false

    init(timeout: TimeInterval) {
        self.timeout = timeout
        self.lineEditor = ConsoleLineEditor(
            prompt: "> ",
            commands: ConsoleCoordinator.supportedCommands,
            messageNames: ConsoleCoordinator.sendableMessageNames
        )
        super.init()
        bluetoothManager.delegate = self

        ConsoleCoordinator.activeCoordinator = self
        installSignalHandlerIfNeeded()

        previousLogHandler = PumpLogging.setHandler { [weak lineEditor] level, label, message in
            guard let lineEditor else { return false }
            if message.isEmpty {
                lineEditor.prepareForExternalOutput()
                Swift.print("")
                lineEditor.externalOutputDidOccur()
                return true
            }
            let isConsoleLog = (label == "TandemCLI.Console")
            let prefix = isConsoleLog ? "" : "[\(level.description)][\(label)] "
            let lines = message.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            lineEditor.prepareForExternalOutput()
            if lines.isEmpty {
                Swift.print(prefix)
            } else {
                for line in lines {
                    Swift.print("\(prefix)\(String(line))")
                }
            }
            lineEditor.externalOutputDidOccur()
            return true
        }
    }

    deinit {
        bluetoothManager.delegate = nil
        eventListenerTask?.cancel()
        _ = PumpLogging.setHandler(previousLogHandler)
        previousLogHandler = nil
        lineEditor.shutdown()
        if ConsoleCoordinator.activeCoordinator === self {
            ConsoleCoordinator.activeCoordinator = nil
        }
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.sync { self.continuation = continuation }
            scheduleTimeout()
            DispatchQueue.main.async {
                self.bluetoothManager.scanForPeripheral()
            }
        }
    }

    private func installSignalHandlerIfNeeded() {
        guard !ConsoleCoordinator.signalHandlerInstalled else { return }
        signal(SIGINT, ConsoleCoordinator.sigintHandler)
        ConsoleCoordinator.signalHandlerInstalled = true
    }

    // MARK: - BluetoothManagerDelegate

    func bluetoothManager(_ manager: BluetoothManager,
                          shouldConnectPeripheral peripheral: CBPeripheral,
                          advertisementData: [String : Any]?) -> Bool {
        return stateQueue.sync {
            if let target = targetPeripheral, target.identifier != peripheral.identifier {
                return false
            }
            if targetPeripheral == nil {
                targetPeripheral = peripheral
                consolePrint("Discovered pump: \(peripheral.name ?? peripheral.identifier.uuidString)")
            }
            return true
        }
    }

    func bluetoothManager(_ manager: BluetoothManager,
                          peripheralManager: PeripheralManager,
                          isReadyWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else {
            consolePrint("Connected. Waiting for configuration...")
        }
    }

    func bluetoothManager(_ manager: BluetoothManager,
                          didCompleteConfiguration peripheralManager: PeripheralManager) {
        let shouldStart: Bool = stateQueue.sync {
            if didStartConsole {
                return false
            }
            didStartConsole = true
            transport = PeripheralManagerTransport(peripheralManager: peripheralManager)
            return true
        }

        guard shouldStart, let transport else { return }

        consolePrint("Peripheral configured.")

        // Run console on background queue
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                self.cancelTimeout()

                // Perform quick JPAKE confirmation
                #if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
                if let derivedSecretData = PumpStateSupplier.getDerivedSecret() {
                    consolePrint("[ConsoleCoordinator] Performing quick JPAKE confirmation...")

                    let builder = JpakeAuthBuilder.initializeWithDerivedSecret(pairingCode: "000000", derivedSecret: derivedSecretData)

                    while let request = builder.nextRequest(), !builder.done() && !builder.invalid() {
                        consolePrint("[ConsoleCoordinator] Sending JPAKE request: \(type(of: request))")
                        let response = try transport.sendMessage(request)
                        consolePrint("[ConsoleCoordinator] Received JPAKE response: \(type(of: response))")
                        builder.processResponse(response)
                    }

                    if builder.invalid() {
                        throw CLIError("JPAKE confirmation failed - invalid credentials")
                    }

                    if builder.done() {
                        consolePrint("[ConsoleCoordinator] Quick JPAKE confirmation completed successfully")
                    }
                }
                #endif

                self.startQualifyingEventListener(peripheralManager: peripheralManager)

                consolePrint("")
                consolePrint("✅ Connected to pump. Console is ready.")
                consolePrint("Type 'help' for available commands or 'exit' to quit.")
                consolePrint("")

                // Run interactive console loop
                self.runConsoleLoop(transport: transport)

                self.finish(.success(()))
            } catch {
                consolePrint("Console setup failed: \(error)")
                self.finish(.failure(CLIError(String(describing: error))))
            }
        }
    }

    func bluetoothManager(_ manager: BluetoothManager,
                          didIdentifyPump manufacturer: String,
                          model: String) {
        consolePrint("Pump model identified: \(manufacturer) \(model)")
    }

    // MARK: - Console Loop

    private func runConsoleLoop(transport: PeripheralManagerTransport) {
        while !shouldExit {
            guard let input = lineEditor.readLine() else {
                consolePrint("Input stream closed. Exiting console...", level: .warning)
                shouldExit = true
                break
            }

            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let command = parts.first?.lowercased() else { continue }

            switch command {
            case "help":
                printHelp()
            case "list":
                printList()
            case "exit", "quit":
                consolePrint("Exiting console...")
                shouldExit = true
            case "send":
                if parts.count < 2 {
                    consolePrint("Error: send command requires a message name", level: .warning)
                    consolePrint("Usage: send <MessageName>", level: .debug)
                } else {
                    let messageName = String(parts[1])
                    handleSendCommand(messageName: messageName, transport: transport)
                }
            default:
                consolePrint("Unknown command: \(command)", level: .warning)
                consolePrint("Type 'help' for available commands", level: .debug)
            }
        }
    }

    private func printHelp() {
        consolePrint("Available commands:")
        consolePrint("  send <MessageName>  Send a parameter-less request message")
        consolePrint("  list                Show sendable request message names")
        consolePrint("  help                Show this help message")
        consolePrint("  exit                Exit the console")
    }

    private func printList() {
        consolePrint("Sendable request messages:")
        for name in ConsoleCoordinator.sendableMessageNames {
            consolePrint("  \(name)")
        }
    }

    private func handleSendCommand(messageName: String, transport: PeripheralManagerTransport) {
        guard let metadata = MessageRegistry.metadata(forName: messageName) else {
            consolePrint("Error: Unknown message type '\(messageName)'", level: .warning)
            consolePrint("Use 'tandemkit-cli list' to see available message names", level: .debug)
            return
        }

        guard metadata.messageType == .Request else {
            consolePrint("Error: '\(messageName)' is a response message. Only request messages can be sent.", level: .warning)
            return
        }

        guard metadata.size == 0 else {
            consolePrint("Error: '\(messageName)' requires parameters. Only parameter-less messages are supported.", level: .warning)
            return
        }

        let message = metadata.type.init(cargo: Data())

        consolePrint("Sending \(messageName)...", level: .debug)
        do {
            let response = try transport.sendMessage(message)
            consolePrint("Response: \(String(describing: type(of: response)))")

            // Display response fields
            if let responseMeta = MessageRegistry.metadata(for: response) {
                consolePrint("  OpCode: \(responseMeta.opCode)")
                consolePrint("  Size: \(responseMeta.size) bytes")
            }
            let fields = messagePropertyDescriptions(response)
            if !fields.isEmpty {
                consolePrint("  Fields:")
                for key in fields.keys.sorted() {
                    if let value = fields[key] {
                        consolePrint("    \(key): \(value)")
                    }
                }
            }
        } catch {
            consolePrint("Error sending message: \(error)", level: .error)
        }
    }

    // MARK: - Helpers

    private func scheduleTimeout() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finish(.failure(CLIError("Console connection timed out after \(Int(self.timeout)) seconds.")))
        }
        timeoutWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + self.timeout, execute: workItem)
    }

    private func cancelTimeout() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
    }

    private func finish(_ result: Result<Void, Error>) {
        let continuation: CheckedContinuation<Void, Error>? = stateQueue.sync {
            defer { self.continuation = nil }
            return self.continuation
        }

        guard let continuation else { return }

        cancelTimeout()

        let priorHandler = previousLogHandler
        previousLogHandler = nil
        _ = PumpLogging.setHandler(priorHandler)

        lineEditor.shutdown()

        eventListenerTask?.cancel()
        eventListenerTask = nil

        DispatchQueue.main.async {
            self.bluetoothManager.permanentDisconnect()
        }

        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

extension ConsoleCoordinator {
    private static func handleSigint(_ signal: Int32) {
        ConsoleLineEditor.handleInterruptSignal()
        ConsoleCoordinator.activeCoordinator?.handleInterruptAndExit()
        exit(signal)
    }

    private func handleInterruptAndExit() {
        consolePrint("\n[ConsoleCoordinator] Received SIGINT (Ctrl-C). Exiting...", level: .warning)
    }

    private func startQualifyingEventListener(peripheralManager: PeripheralManager) {
        eventListenerTask?.cancel()
        eventListenerTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            await self.listenForQualifyingEvents(peripheralManager: peripheralManager)
        }
    }

    private func listenForQualifyingEvents(peripheralManager: PeripheralManager) async {
        let characteristic = CharacteristicUUID.QUALIFYING_EVENTS_CHARACTERISTICS

        while !Task.isCancelled && shouldContinueConsole() {
            do {
                let packet = try peripheralManager.performSync { manager -> Data? in
                    try manager.readMessagePacket(for: characteristic, timeout: 0.2)
                }

                guard let data = packet, !data.isEmpty else {
                    continue
                }

                await processQualifyingEventPayload(data)
            } catch {
                if Task.isCancelled || !shouldContinueConsole() {
                    break
                }

                let description = String(describing: error)
                if description.lowercased().contains("timeout") {
                    continue
                }

                consolePrint("\n[ConsoleCoordinator] Qualifying event listener error: \(error)")
                do {
                    try await Task.sleep(nanoseconds: 200_000_000)
                } catch {
                    break
                }
            }
        }
    }

    private func shouldContinueConsole() -> Bool {
        stateQueue.sync { !shouldExit }
    }

    private func processQualifyingEventPayload(_ data: Data) async {
        var index = 0
        while index + 4 <= data.count {
            let chunk = data[index..<(index + 4)]
            let chunkData = Data(chunk)

            let mask = chunkData.withUnsafeBytes { pointer -> UInt32 in
                guard pointer.count >= MemoryLayout<UInt32>.size else { return 0 }
                return UInt32(littleEndian: pointer.load(as: UInt32.self))
            }

            let events = QualifyingEvent.fromRawBytes(chunkData)

            if mask != 0 {
                await MainActor.run {
                    self.reportQualifyingEvents(mask: mask, events: events)
                }
            }

            index += 4
        }

        let remainder = data.count % 4
        if remainder != 0 {
            let tail = data.suffix(remainder)
            consolePrint("\n[ConsoleCoordinator] Ignored trailing \(remainder) bytes from qualifying events payload: \(tail.hexadecimalString)")
        }
    }

    @MainActor
    private func reportQualifyingEvents(mask: UInt32, events: Set<QualifyingEvent>) {
        let maskHex = String(format: "0x%08X", mask)
        let eventNames = events.sorted(by: { displayName(for: $0) < displayName(for: $1) }).map { displayName(for: $0) }

        consolePrint("\n[QualifyingEvents] Received mask \(maskHex)")

        if eventNames.isEmpty {
            consolePrint("[QualifyingEvents] No events decoded from mask")
        } else {
            consolePrint("[QualifyingEvents] Events: \(eventNames.joined(separator: ", "))")
        }

        let suggested = QualifyingEvent.groupSuggestedHandlers(events)
        if !suggested.isEmpty {
            let requestNames = suggested.compactMap { message -> String? in
                if let metadata = MessageRegistry.metadata(for: message) {
                    return metadata.name
                }
                return String(describing: type(of: message))
            }
            if !requestNames.isEmpty {
                consolePrint("[QualifyingEvents] Suggested follow-up requests: \(requestNames.joined(separator: ", "))")
            }
        }

        if shouldContinueConsole() {
            lineEditor.externalOutputDidOccur()
        }
    }

    private func displayName(for event: QualifyingEvent) -> String {
        switch event {
        case .alert: return "Alert"
        case .alarm: return "Alarm"
        case .reminder: return "Reminder"
        case .malfunction: return "Malfunction"
        case .cgmAlert: return "CGM Alert"
        case .homeScreenChange: return "Home Screen Change"
        case .pumpSuspend: return "Pump Suspend"
        case .pumpResume: return "Pump Resume"
        case .timeChange: return "Time Change"
        case .basalChange: return "Basal Change"
        case .bolusChange: return "Bolus Change"
        case .iobChange: return "IOB Change"
        case .extendedBolusChange: return "Extended Bolus Change"
        case .profileChange: return "Profile Change"
        case .bg: return "BG"
        case .cgmChange: return "CGM Change"
        case .battery: return "Battery"
        case .basalIQ: return "Basal-IQ"
        case .remainingInsulin: return "Remaining Insulin"
        case .suspendComm: return "Suspend Comm"
        case .activeSegmentChange: return "Active Segment Change"
        case .basalIQStatus: return "Basal-IQ Status"
        case .controlIQInfo: return "Control-IQ Info"
        case .controlIQSleep: return "Control-IQ Sleep"
        case .bolusPermissionRevoked: return "Bolus Permission Revoked"
        }
    }
}

private extension ConsoleCoordinator {
    func consolePrint(_ text: String, level: PumpLogger.Level = .info) {
        logger.log(level, text)
    }
}

// MARK: - Console Line Editing

private final class ConsoleLineEditor {
    private enum CompletionDecision {
        case none
        case list([String])
        case replace(String)
    }

    private let prompt: String
    private let promptData: Data
    private let commands: [String]
    private let messageNames: [String]
    private let inputHandle = FileHandle.standardInput
    private let outputHandle = FileHandle.standardOutput
    private let lock = NSLock()
    private static weak var activeEditor: ConsoleLineEditor?

    private var buffer: [UInt8] = []
    private var lastRenderedLength: Int = 0
    private var isActive: Bool = false

    #if canImport(Darwin)
    private var originalTermios = termios()
    private var rawModeEnabled = false
    #endif

    init(prompt: String, commands: [String], messageNames: [String]) {
        self.prompt = prompt
        self.promptData = Data(prompt.utf8)
        self.commands = commands
        self.messageNames = messageNames
        ConsoleLineEditor.activeEditor = self
        enableRawMode()
    }

    func readLine() -> String? {
        enableRawMode()

        lock.lock()
        buffer.removeAll(keepingCapacity: true)
        lastRenderedLength = 0
        isActive = true
        lock.unlock()

        writeData(promptData)

        while true {
            guard let byte = readByte() else {
                lock.lock()
                isActive = false
                lock.unlock()
                return nil
            }

            switch byte {
            case 10, 13:
                lock.lock()
                let line = String(bytes: buffer, encoding: .utf8) ?? ""
                buffer.removeAll(keepingCapacity: true)
                lastRenderedLength = 0
                isActive = false
                lock.unlock()

                write("\r\n")
                return line

            case 4:
                lock.lock()
                let empty = buffer.isEmpty
                if empty {
                    isActive = false
                    lock.unlock()
                    write("\r\n")
                    return nil
                }
                lock.unlock()

            case 9:
                handleTab()

            case 8, 127:
                handleBackspace()

            default:
                if byte >= 32 {
                    handleCharacter(byte)
                }
            }
        }
    }

    func externalOutputDidOccur() {
        lock.lock()
        guard isActive else {
            lock.unlock()
            return
        }
        refreshLineLocked()
        lock.unlock()
    }

    func shutdown() {
        lock.lock()
        isActive = false
        lock.unlock()
        restoreRawMode()
        if ConsoleLineEditor.activeEditor === self {
            ConsoleLineEditor.activeEditor = nil
        }
    }

    deinit {
        shutdown()
    }

    // MARK: - Input Helpers

    private func readByte() -> UInt8? {
        if #available(macOS 10.15.4, *) {
            do {
                if let data = try inputHandle.read(upToCount: 1), let byte = data.first {
                    return byte
                }
                return nil
            } catch {
                return nil
            }
        } else {
            let data = inputHandle.readData(ofLength: 1)
            return data.first
        }
    }

    private func handleCharacter(_ byte: UInt8) {
        lock.lock()
        buffer.append(byte)
        lastRenderedLength = buffer.count
        lock.unlock()

        writeData(Data([byte]))
    }

    private func handleBackspace() {
        lock.lock()
        guard !buffer.isEmpty else {
            lock.unlock()
            write("\u{7}")
            return
        }
        buffer.removeLast()
        lastRenderedLength = buffer.count
        lock.unlock()

        writeData(Data([8, 32, 8]))
    }

    private func handleTab() {
        let currentLine = currentBufferString()
        let decision = completionDecision(for: currentLine)

        switch decision {
        case .none:
            write("\u{7}")

        case .list(let options):
            guard !options.isEmpty else {
                write("\u{7}")
                return
            }
            write("\n")
            displayOptions(options)
            lock.lock()
            refreshLineLocked()
            lock.unlock()

        case .replace(let newLine):
            replaceCurrentLine(with: newLine)
        }
    }

    private func replaceCurrentLine(with newLine: String) {
        lock.lock()
        let oldLength = lastRenderedLength
        buffer = Array(newLine.utf8)
        lastRenderedLength = buffer.count
        writePromptAndBufferLocked(oldLength: oldLength)
        lock.unlock()
    }

    private func refreshLineLocked() {
        let oldLength = lastRenderedLength
        lastRenderedLength = buffer.count
        writePromptAndBufferLocked(oldLength: oldLength)
    }

    // MARK: - Completion Logic

    private func completionDecision(for line: String) -> CompletionDecision {
        let trimmedLeading = line.drop { $0.isWhitespace }
        let tokens = trimmedLeading.split(separator: " ", omittingEmptySubsequences: true).map { String($0) }
        let hasTrailingSpace = line.last?.isWhitespace ?? false
        let lastWhitespaceIndex = line.lastIndex(where: { $0 == " " || $0 == "\t" })
        let tokenStart = lastWhitespaceIndex.map { line.index(after: $0) } ?? line.startIndex
        let prefix = String(line[..<tokenStart])
        let currentToken = hasTrailingSpace ? "" : String(line[tokenStart...])

        if tokens.isEmpty {
            return commandCompletion(prefix: prefix, token: currentToken)
        }

        if tokens.count == 1 && !hasTrailingSpace {
            return commandCompletion(prefix: prefix, token: currentToken)
        }

        guard let firstToken = tokens.first?.lowercased() else {
            return .none
        }

        if firstToken == "send" {
            if tokens.count == 1 && hasTrailingSpace {
                return messageCompletion(prefix: prefix, token: "")
            } else if tokens.count >= 2 {
                return messageCompletion(prefix: prefix, token: currentToken)
            }
        }

        return .none
    }

    private func commandCompletion(prefix: String, token: String) -> CompletionDecision {
        let lowerToken = token.lowercased()
        let matches = commands.filter { command in
            lowerToken.isEmpty ? true : command.lowercased().hasPrefix(lowerToken)
        }

        guard !matches.isEmpty else {
            return .none
        }

        if matches.count == 1 {
            var completed = prefix + matches[0]
            if matches[0] == "send" && !completed.hasSuffix(" ") {
                completed += " "
            }
            return .replace(completed)
        }

        return .list(matches)
    }

    private func messageCompletion(prefix: String, token: String) -> CompletionDecision {
        let lowerToken = token.lowercased()
        let matches = messageNames.filter { name in
            lowerToken.isEmpty ? true : name.lowercased().hasPrefix(lowerToken)
        }

        guard !matches.isEmpty else {
            return .none
        }

        if matches.count == 1 {
            let completed = prefix + matches[0]
            return .replace(completed)
        }

        return .list(matches)
    }

    // MARK: - Output Helpers

    private func displayOptions(_ options: [String]) {
        let sorted = options.sorted()
        for option in sorted {
            write(option)
            write("\n")
        }
    }

    private func writePromptAndBufferLocked(oldLength: Int) {
        let bufferData = Data(buffer)
        writeData(Data("\r".utf8))
        writeData(promptData)
        writeData(bufferData)

        if oldLength > buffer.count {
            let diff = oldLength - buffer.count
            let spaces = String(repeating: " ", count: diff)
            write(spaces)
            writeData(Data("\r".utf8))
            writeData(promptData)
            writeData(bufferData)
        }
    }

    private func currentBufferString() -> String {
        lock.lock()
        let result = String(bytes: buffer, encoding: .utf8) ?? ""
        lock.unlock()
        return result
    }

    private func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        writeData(data)
    }

    private func writeData(_ data: Data) {
        outputHandle.write(data)
    }

    func prepareForExternalOutput() {
        lock.lock()
        guard isActive else {
            lock.unlock()
            return
        }
        clearLineLocked()
        lock.unlock()
    }

    private func clearLineLocked() {
        let total = promptData.count + lastRenderedLength
        writeData(Data("\r".utf8))
        if total > 0 {
            write(String(repeating: " ", count: total))
            writeData(Data("\r".utf8))
        }
    }

    private func enableRawMode() {
        #if canImport(Darwin)
        guard !rawModeEnabled else { return }
        var term = termios()
        if tcgetattr(STDIN_FILENO, &term) == 0 {
            originalTermios = term
            var raw = term
            cfmakeraw(&raw)
            raw.c_lflag |= tcflag_t(ISIG)
            if tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 {
                rawModeEnabled = true
            }
        }
        #endif
    }

    private func restoreRawMode() {
        #if canImport(Darwin)
        guard rawModeEnabled else { return }
        var term = originalTermios
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &term)
        rawModeEnabled = false
        #endif
    }

    static func handleInterruptSignal() {
        activeEditor?.restoreRawMode()
    }
}
#endif
