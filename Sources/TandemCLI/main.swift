import Foundation
import TandemCore
import TandemBLE
import TandemKit
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

    struct SendOptions {
        var messageName: String = ""
        var timeout: TimeInterval = 30.0
        var format: OutputFormat = .text
        var peripheralId: String?
        var derivedSecret: String?
        var serverNonce: String?
        var authKey: String?
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
                options.peripheralId = args[index]
            case "--derived-secret":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --derived-secret.")
                }
                options.derivedSecret = args[index]
            case "--server-nonce":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --server-nonce.")
                }
                options.serverNonce = args[index]
            case "--auth-key":
                index += 1
                if index >= args.count {
                    throw CLIError("Missing value for --auth-key.")
                }
                options.authKey = args[index]
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

        // Parse peripheral ID if provided
        var targetPeripheralId: UUID?
        if let peripheralIdString = options.peripheralId {
            guard let uuid = UUID(uuidString: peripheralIdString) else {
                throw CLIError("Invalid peripheral ID format. Expected UUID (e.g., 12345678-1234-1234-1234-123456789ABC).")
            }
            targetPeripheralId = uuid
        }

        // If credentials are provided, set them up
        if let derivedSecretHex = options.derivedSecret,
           let serverNonceHex = options.serverNonce,
           let authKeyHex = options.authKey {

            // Parse hex strings
            let derivedSecret = try dataFromHex(derivedSecretHex)
            let serverNonce = try dataFromHex(serverNonceHex)
            let _ = try dataFromHex(authKeyHex)  // Validate authKey format but don't use it directly

            // Store in PumpStateSupplier
            PumpStateSupplier.storePairingArtifacts(derivedSecret: derivedSecret, serverNonce: serverNonce)

            print("Using provided pairing credentials")
            print("  Derived secret: \(derivedSecret.hexadecimalString.prefix(16))...")
            print("  Server nonce: \(serverNonce.hexadecimalString.prefix(16))...")
            if let peripheralId = targetPeripheralId {
                print("  Target peripheral: \(peripheralId.uuidString)")
            }
        } else if options.derivedSecret != nil || options.serverNonce != nil || options.authKey != nil {
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
#endif
