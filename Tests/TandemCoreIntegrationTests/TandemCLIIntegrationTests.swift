import Foundation
import XCTest
@testable import TandemCore
@testable import TandemCLI

final class TandemCLIIntegrationTests: XCTestCase {
    func testMessageFixturesDecodeAndEncode() async throws {
        let fixtures = try loadFixtures()
        XCTAssertFalse(fixtures.isEmpty, "No fixtures defined in IntegrationMessages.json")

        let pumpx2CLI = PumpX2CLI.locate(projectRoot: projectRootURL)

        for fixture in fixtures {
            let sanitizedPackets = fixture.packets.map { sanitizeHexInput($0).lowercased() }

            var decodeOptions = TandemCLIMain.DecodeOptions()
            decodeOptions.packets = sanitizedPackets
            let (decodedOutput, message) = try TandemCLIMain.decode(options: decodeOptions)

            XCTAssertEqual(
                decodedOutput.message.name,
                fixture.messageType,
                "Unexpected message type for \(fixture.displayName)."
            )
            XCTAssertTrue(
                String(describing: type(of: message)).hasSuffix(fixture.messageType) ||
                    String(reflecting: type(of: message)).hasSuffix(".\(fixture.messageType)"),
                "Decoded message instance for \(fixture.displayName) had unexpected type: \(type(of: message))"
            )

            let tandemFields = try decodeFields(
                from: decodedOutput.message.fields,
                messageName: fixture.displayName,
                source: "TandemKit decode"
            )
            try assertFields(
                expected: fixture.expectedFields,
                actual: tandemFields,
                messageName: fixture.displayName,
                source: "TandemKit decode"
            )

            XCTAssertEqual(
                decodedOutput.packets,
                sanitizedPackets,
                "Sanitized packets for \(fixture.displayName) did not match input."
            )

            var encodeOptions = TandemCLIMain.EncodeOptions()
            encodeOptions.messageName = decodedOutput.message.name
            encodeOptions.txId = decodedOutput.header.packetTxId
            encodeOptions.cargo = decodedOutput.message.cargo
            encodeOptions.allowInsulinActions = decodedOutput.message.modifiesInsulinDelivery

            let optionsForEncoding = encodeOptions
            let (encodedOutput, _) = try await MainActor.run {
                try TandemCLIMain.encode(options: optionsForEncoding)
            }

            let encodedPackets = encodedOutput.packets.map { $0.hex.lowercased() }
            XCTAssertEqual(
                encodedPackets,
                sanitizedPackets,
                "Encoded packets for \(fixture.displayName) differed from expected packets."
            )

            let expectedMerged = sanitizedPackets.joined()
            XCTAssertEqual(
                encodedOutput.mergedHex.lowercased(),
                expectedMerged,
                "Merged packet output for \(fixture.displayName) did not match expected hex."
            )

            if let pumpx2CLI {
                let pumpx2Result = try pumpx2CLI.decode(packets: sanitizedPackets)

                guard let parsed = pumpx2Result.parsed else {
                    XCTFail("PumpX2 CLI failed to parse \(fixture.displayName). stderr: \(pumpx2Result.stderr)")
                    continue
                }

                XCTAssertTrue(
                    parsed.name.hasSuffix(fixture.messageType),
                    "PumpX2 CLI decoded unexpected message name \(parsed.name) for \(fixture.displayName)."
                )

                XCTAssertEqual(
                    parsed.cargoHex.lowercased(),
                    decodedOutput.message.cargo.lowercased(),
                    "PumpX2 CLI decoded cargo for \(fixture.displayName) differed from TandemKit."
                )

                if let expected = fixture.expectedFields {
                    let normalized = normalizePumpX2Fields(expected: expected, actual: parsed.params ?? [:])
                    try assertFields(
                        expected: expected,
                        actual: normalized,
                        messageName: fixture.displayName,
                        source: "PumpX2 CLI decode"
                    )
                }

                XCTAssertEqual(
                    pumpx2Result.packets,
                    sanitizedPackets,
                    "PumpX2 CLI raw packets for \(fixture.displayName) differed from expected input."
                )
            }
        }
    }

    private var projectRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadFixtures() throws -> [MessageFixture] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "IntegrationMessages", withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([MessageFixture].self, from: data)
    }

    private func decodeFields(
        from fields: [String: AnyEncodable],
        messageName: String,
        source: String
    ) throws -> [String: FixtureFieldValue] {
        var decoded: [String: FixtureFieldValue] = [:]
        for (name, value) in fields {
            decoded[name] = try decodeFieldValue(
                from: value,
                fieldName: name,
                messageName: messageName,
                source: source
            )
        }
        return decoded
    }

    private func assertFields(
        expected: [String: FixtureFieldValue]?,
        actual: [String: FixtureFieldValue],
        messageName: String,
        source: String
    ) throws {
        guard let expected else { return }
        for (fieldName, expectedValue) in expected {
            guard let actualValue = actual[fieldName] else {
                XCTFail("Expected field \(fieldName) missing in \(messageName) (\(source)).")
                continue
            }
            let normalizedExpected: FixtureFieldValue
            if case let .string(value) = expectedValue {
                normalizedExpected = .string(value.lowercased())
            } else {
                normalizedExpected = expectedValue
            }
            let normalizedActual = normalizeFixtureValue(actualValue, expected: normalizedExpected)
            XCTAssertEqual(
                normalizedActual,
                normalizedExpected,
                "Field \(fieldName) mismatch for \(messageName) (\(source))."
            )
        }
    }

    private func decodeFieldValue(
        from value: AnyEncodable?,
        fieldName: String,
        messageName: String,
        source: String
    ) throws -> FixtureFieldValue {
        guard let value else {
            throw FixtureComparisonError.missingField(fieldName)
        }
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(FixtureFieldValue.self, from: data)
    }
}

private struct MessageFixture: Decodable {
    let description: String?
    let messageType: String
    let packets: [String]
    let expectedFields: [String: FixtureFieldValue]?

    var displayName: String { description ?? messageType }
}

private struct PumpX2CLIRequest: Encodable {
    let type: String
    let btChar: String
    let value: String
    let extraValueStr: [String]?
    let ts: String

    init(packets: [String]) {
        self.type = "read"
        self.btChar = ""
        self.value = packets.first ?? ""
        let extras = Array(packets.dropFirst())
        self.extraValueStr = extras.isEmpty ? nil : extras
        self.ts = "0"
    }
}

private struct PumpX2JSONOutput: Decodable {
    struct Parsed: Decodable {
        let name: String
        let params: [String: FixtureFieldValue]?
        let cargoHex: String
    }

    struct Raw: Decodable {
        let value: String
        let extraValueStr: [String]?
    }

    let parsed: Parsed?
    let raw: Raw
}

private struct PumpX2CLI {
    struct Invocation {
        let executableURL: URL
        let arguments: [String]
    }

    struct DecodedMessage {
        let parsed: PumpX2JSONOutput.Parsed?
        let packets: [String]
        let rawOutput: String
        let stderr: String
    }

    private let invocation: Invocation

    static func locate(projectRoot: URL) -> PumpX2CLI? {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment

        if let explicitPath = env["PUMPX2_CLIPARSER_PATH"], !explicitPath.isEmpty {
            let url = URL(fileURLWithPath: explicitPath)
            if fm.fileExists(atPath: url.path) {
                if url.pathExtension.lowercased() == "jar" {
                    return PumpX2CLI(invocation: invocation(forJar: url))
                } else {
                    return PumpX2CLI(invocation: invocation(forExecutable: url))
                }
            }
        }

        let potentialRoots = [
            projectRoot.appendingPathComponent("pumpX2"),
            projectRoot.deletingLastPathComponent().appendingPathComponent("pumpX2")
        ]

        for root in potentialRoots {
            if let cli = locateInPumpX2Repository(root) {
                return cli
            }
        }

        return nil
    }

    private static func locateInPumpX2Repository(_ root: URL) -> PumpX2CLI? {
        let fm = FileManager.default
        let installPath = root
            .appendingPathComponent("cliparser")
            .appendingPathComponent("build")
            .appendingPathComponent("install")
            .appendingPathComponent("cliparser")
            .appendingPathComponent("bin")
            .appendingPathComponent("cliparser")

        if fm.isExecutableFile(atPath: installPath.path) {
            return PumpX2CLI(invocation: invocation(forExecutable: installPath))
        }

        let libsPath = root
            .appendingPathComponent("cliparser")
            .appendingPathComponent("build")
            .appendingPathComponent("libs")

        if let jar = locateCliparserJar(in: libsPath) {
            return PumpX2CLI(invocation: invocation(forJar: jar))
        }

        return nil
    }

    private static func locateCliparserJar(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        return contents
            .filter { $0.pathExtension.lowercased() == "jar" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first { $0.lastPathComponent.lowercased().contains("cliparser") }
    }

    private static func invocation(forExecutable executable: URL) -> Invocation {
        Invocation(executableURL: executable, arguments: [])
    }

    private static func invocation(forJar jar: URL) -> Invocation {
        Invocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["java", "-jar", jar.path]
        )
    }

    func decode(packets: [String]) throws -> DecodedMessage {
        let request = PumpX2CLIRequest(packets: packets)
        let requestData = try JSONEncoder().encode(request)
        guard let requestString = String(data: requestData, encoding: .utf8) else {
            throw PumpX2CLIError.encodingFailure
        }

        let output = try run(arguments: ["json", requestString])
        let trimmed = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw PumpX2CLIError.invalidOutput(output.stdout)
        }

        let decoded = try JSONDecoder().decode(PumpX2JSONOutput.self, from: data)
        let packets = ([decoded.raw.value] + (decoded.raw.extraValueStr ?? []))
            .map { sanitizeHexInput($0).lowercased() }

        return DecodedMessage(
            parsed: decoded.parsed,
            packets: packets,
            rawOutput: trimmed,
            stderr: output.stderr
        )
    }

    private func run(arguments trailing: [String]) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments + trailing
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stdoutString = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw PumpX2CLIError.nonZeroExit(
                code: process.terminationStatus,
                stdout: stdoutString,
                stderr: stderrString
            )
        }

        return ProcessOutput(stdout: stdoutString, stderr: stderrString)
    }
}

private struct ProcessOutput {
    let stdout: String
    let stderr: String
}

private enum PumpX2CLIError: Error {
    case encodingFailure
    case invalidOutput(String)
    case nonZeroExit(code: Int32, stdout: String, stderr: String)
}

private enum FixtureComparisonError: Error {
    case missingField(String)
}

private enum FixtureFieldValue: Equatable, Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([FixtureFieldValue])
    case object([String: FixtureFieldValue])
    case null

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var dictionary: [String: FixtureFieldValue] = [:]
            for key in keyed.allKeys {
                dictionary[key.stringValue] = try keyed.decode(FixtureFieldValue.self, forKey: key)
            }
            self = .object(dictionary)
            return
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            var array: [FixtureFieldValue] = []
            while !unkeyed.isAtEnd {
                let value = try unkeyed.decode(FixtureFieldValue.self)
                array.append(value)
            }
            self = .array(array)
            return
        }
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported value in fixtures")
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension FixtureFieldValue {
    static func == (lhs: FixtureFieldValue, rhs: FixtureFieldValue) -> Bool {
        switch (lhs, rhs) {
        case let (.string(a), .string(b)):
            return a == b
        case let (.int(a), .int(b)):
            return a == b
        case let (.int(a), .double(b)):
            return Double(a) == b
        case let (.double(a), .int(b)):
            return a == Double(b)
        case let (.double(a), .double(b)):
            return a == b
        case let (.bool(a), .bool(b)):
            return a == b
        case let (.array(a), .array(b)):
            return a == b
        case let (.object(a), .object(b)):
            return a == b
        case (.null, .null):
            return true
        default:
            return false
        }
    }

    var arrayValue: [FixtureFieldValue]? {
        if case let .array(value) = self {
            return value
        }
        return nil
    }

    var objectValue: [String: FixtureFieldValue]? {
        if case let .object(value) = self {
            return value
        }
        return nil
    }

    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    var intValue: Int? {
        switch self {
        case let .int(value):
            return value
        case let .double(value) where value.rounded() == value:
            return Int(value)
        default:
            return nil
        }
    }

    var byteValue: UInt8? {
        guard let value = intValue, (0...255).contains(value) else { return nil }
        return UInt8(value)
    }

    var hexStringRepresentation: String? {
        if let stringValue {
            return stringValue.lowercased()
        }
        if let array = arrayValue, let hex = array.hexStringIfByteArray() {
            return hex
        }
        if let object = objectValue {
            if let array = object["array"]?.arrayValue, let hex = array.hexStringIfByteArray() {
                return hex
            }
            if let bytes = object["bytes"]?.arrayValue, let hex = bytes.hexStringIfByteArray() {
                return hex
            }
            if let data = object["data"]?.arrayValue, let hex = data.hexStringIfByteArray() {
                return hex
            }
        }
        return nil
    }
}

private extension Array where Element == FixtureFieldValue {
    func hexStringIfByteArray() -> String? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count)
        for element in self {
            guard let byte = element.byteValue else { return nil }
            bytes.append(byte)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

private func normalizeFixtureValue(_ actual: FixtureFieldValue, expected: FixtureFieldValue) -> FixtureFieldValue {
    switch expected {
    case .string:
        if let hex = actual.hexStringRepresentation {
            return .string(hex)
        }
        return actual
    case let .array(expectedArray):
        guard case let .array(actualArray) = actual else { return actual }
        var normalized: [FixtureFieldValue] = []
        normalized.reserveCapacity(actualArray.count)
        for (index, element) in actualArray.enumerated() {
            if index < expectedArray.count {
                normalized.append(normalizeFixtureValue(element, expected: expectedArray[index]))
            } else if let lastExpected = expectedArray.last {
                normalized.append(normalizeFixtureValue(element, expected: lastExpected))
            } else {
                normalized.append(element)
            }
        }
        return .array(normalized)
    case let .object(expectedObject):
        guard case let .object(actualObject) = actual else { return actual }
        var normalized = actualObject
        for (key, expectedValue) in expectedObject {
            if let current = actualObject[key] {
                normalized[key] = normalizeFixtureValue(current, expected: expectedValue)
            }
        }
        return .object(normalized)
    default:
        return actual
    }
}

private func normalizePumpX2Fields(
    expected: [String: FixtureFieldValue],
    actual: [String: FixtureFieldValue]
) -> [String: FixtureFieldValue] {
    var normalized: [String: FixtureFieldValue] = actual
    for (key, expectedValue) in expected {
        if let current = actual[key] {
            normalized[key] = normalizeFixtureValue(current, expected: expectedValue)
        }
    }
    return normalized
}
