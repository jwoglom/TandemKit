import Foundation
import TandemCore
import TandemBLE

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

struct AnyEncodable: Encodable {
    private let value: Any

    init(_ value: Any?) {
        if let v = value {
            self.value = v
        } else {
            self.value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        switch value {
        case is NSNull:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case let bool as Bool:
            var container = encoder.singleValueContainer()
            try container.encode(bool)
        case let int as Int:
            var container = encoder.singleValueContainer()
            try container.encode(int)
        case let int8 as Int8:
            var container = encoder.singleValueContainer()
            try container.encode(int8)
        case let int16 as Int16:
            var container = encoder.singleValueContainer()
            try container.encode(int16)
        case let int32 as Int32:
            var container = encoder.singleValueContainer()
            try container.encode(int32)
        case let int64 as Int64:
            var container = encoder.singleValueContainer()
            try container.encode(int64)
        case let uint as UInt:
            var container = encoder.singleValueContainer()
            try container.encode(uint)
        case let uint8 as UInt8:
            var container = encoder.singleValueContainer()
            try container.encode(uint8)
        case let uint16 as UInt16:
            var container = encoder.singleValueContainer()
            try container.encode(uint16)
        case let uint32 as UInt32:
            var container = encoder.singleValueContainer()
            try container.encode(uint32)
        case let uint64 as UInt64:
            var container = encoder.singleValueContainer()
            try container.encode(uint64)
        case let double as Double:
            var container = encoder.singleValueContainer()
            try container.encode(double)
        case let float as Float:
            var container = encoder.singleValueContainer()
            try container.encode(float)
        case let string as String:
            var container = encoder.singleValueContainer()
            try container.encode(string)
        case let date as Date:
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSince1970)
        case let data as Data:
            var container = encoder.singleValueContainer()
            try container.encode(data.hexadecimalString)
        case let array as [Any?]:
            var container = encoder.unkeyedContainer()
            for element in array {
                try container.encode(AnyEncodable(element))
            }
        case let array as [Any]:
            var container = encoder.unkeyedContainer()
            for element in array {
                try container.encode(AnyEncodable(element))
            }
        case let set as Set<AnyHashable>:
            var container = encoder.unkeyedContainer()
            for element in set {
                try container.encode(AnyEncodable(element))
            }
        case let dict as [String: Any]:
            var container = encoder.container(keyedBy: AnyCodingKey.self)
            for (key, val) in dict {
                try container.encode(AnyEncodable(val), forKey: AnyCodingKey(stringValue: key)!)
            }
        case let dict as [AnyHashable: Any]:
            var container = encoder.container(keyedBy: AnyCodingKey.self)
            for (key, val) in dict {
                try container.encode(AnyEncodable(val), forKey: AnyCodingKey(stringValue: String(describing: key))!)
            }
        case let convertible as CustomStringConvertible:
            var container = encoder.singleValueContainer()
            try container.encode(convertible.description)
        default:
            var container = encoder.singleValueContainer()
            try container.encode(String(describing: value))
        }
    }
}

func unwrapOptional(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else {
        return value
    }
    if let child = mirror.children.first {
        return child.value
    }
    return nil
}

func collectProperties(from mirror: Mirror?) -> [(String, Any)] {
    guard let mirror else { return [] }
    var result: [(String, Any)] = []
    for child in mirror.children {
        if let label = child.label {
            result.append((label, child.value))
        }
    }
    result.append(contentsOf: collectProperties(from: mirror.superclassMirror))
    return result
}

func messageProperties(_ message: Message) -> [String: AnyEncodable] {
    var dict: [String: AnyEncodable] = [:]
    for (label, rawValue) in collectProperties(from: Mirror(reflecting: message)) {
        guard label != "cargo" else { continue }
        let unwrapped = unwrapOptional(rawValue)
        dict[label] = AnyEncodable(unwrapped)
    }
    return dict
}

func messagePropertyDescriptions(_ message: Message) -> [String: String] {
    var dict: [String: String] = [:]
    for (label, rawValue) in collectProperties(from: Mirror(reflecting: message)) {
        guard label != "cargo" else { continue }
        let value = unwrapOptional(rawValue)
        dict[label] = describeValue(value)
    }
    return dict
}

func describeValue(_ value: Any?) -> String {
    guard let value else { return "nil" }
    if let data = value as? Data {
        return data.hexadecimalString
    }
    if let array = value as? [Any] {
        return "[" + array.map { describeValue($0) }.joined(separator: ", ") + "]"
    }
    if let dict = value as? [String: Any] {
        let body = dict.sorted { $0.key < $1.key }.map { "\($0.key): \(describeValue($0.value))" }.joined(separator: ", ")
        return "{" + body + "}"
    }
    if let set = value as? Set<AnyHashable> {
        return "{" + set.map { String(describing: $0) }.sorted().joined(separator: ", ") + "}"
    }
    if let convertible = value as? CustomStringConvertible {
        return convertible.description
    }
    return String(describing: value)
}

struct MessageInfo: Encodable {
    let name: String
    let type: String
    let characteristic: String
    let characteristicUUID: String
    let opCode: UInt8
    let expectedCargoSize: Int
    let payloadLength: Int
    let signed: Bool
    let variableSize: Bool
    let stream: Bool
    let modifiesInsulinDelivery: Bool
    let cargo: String
    let fields: [String: AnyEncodable]
}

struct DecodedMessageOutput: Encodable {
    struct Header: Encodable {
        let packetsRemaining: UInt8
        let packetTxId: UInt8
        let messageTxId: UInt8
        let declaredPayloadSize: Int
        let actualPayloadSize: Int
        let crc: String
    }

    let header: Header
    let message: MessageInfo
    let packets: [String]
}

struct EncodedMessageOutput: Encodable {
    struct Packet: Encodable {
        let index: Int
        let packetsRemaining: UInt8
        let txId: UInt8
        let hex: String
    }

    let message: MessageInfo
    let packets: [Packet]
    let mergedHex: String
}

func buildMessageInfo(metadata: MessageMetadata, message: Message, cargo: Data, payloadLength: Int? = nil) -> MessageInfo {
    MessageInfo(
        name: metadata.name,
        type: String(describing: metadata.messageType),
        characteristic: metadata.characteristic.rawValue,
        characteristicUUID: metadata.characteristic.rawValue,
        opCode: metadata.opCode,
        expectedCargoSize: metadata.size,
        payloadLength: payloadLength ?? cargo.count,
        signed: metadata.signed,
        variableSize: metadata.variableSize,
        stream: metadata.stream,
        modifiesInsulinDelivery: metadata.modifiesInsulinDelivery,
        cargo: cargo.hexadecimalString,
        fields: messageProperties(message)
    )
}

func buildDecodedOutput(metadata: MessageMetadata,
                        message: Message,
                        cargo: Data,
                        header: PacketHeader,
                        crc: Data,
                        packets: [String]) -> DecodedMessageOutput {
    let info = buildMessageInfo(metadata: metadata, message: message, cargo: cargo, payloadLength: cargo.count)
    let headerInfo = DecodedMessageOutput.Header(packetsRemaining: header.packetsRemaining,
                                                 packetTxId: header.packetTxId,
                                                 messageTxId: header.messageTxId,
                                                 declaredPayloadSize: header.declaredPayloadLength,
                                                 actualPayloadSize: cargo.count,
                                                 crc: crc.hexadecimalString)
    return DecodedMessageOutput(header: headerInfo, message: info, packets: packets)
}

func buildEncodedOutput(metadata: MessageMetadata,
                        message: Message,
                        cargo: Data,
                        packets: [Packet],
                        merged: Data) -> EncodedMessageOutput {
    let packetInfos = packets.enumerated().map { index, packet in
        EncodedMessageOutput.Packet(index: index,
                                    packetsRemaining: packet.packetsRemaining,
                                    txId: packet.txId,
                                    hex: packet.build.hexadecimalString)
    }
    let info = buildMessageInfo(metadata: metadata, message: message, cargo: cargo)
    return EncodedMessageOutput(message: info,
                                packets: packetInfos,
                                mergedHex: merged.hexadecimalString)
}

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    if let string = String(data: data, encoding: .utf8) {
        print(string)
    }
}
