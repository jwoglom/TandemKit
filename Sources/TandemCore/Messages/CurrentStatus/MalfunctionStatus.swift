import Foundation

/// Request any malfunction codes from the pump.
public class MalfunctionStatusRequest: Message {
    public static let props = MessageProps(
        opCode: 120,
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "MalfunctionStatusRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response with malfunction codes.
public class MalfunctionStatusResponse: Message, NotificationMessage, NotificationEnum {
    public static let props = MessageProps(
        opCode: 121,
        size: 11,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        variableSize: true
    )

    public var cargo: Data
    public var codeA: UInt32
    public var codeB: UInt32
    public var remaining: Data

    public required init(cargo: Data) {
        self.cargo = cargo
        codeA = Bytes.readUint32(cargo, 0)
        codeB = Bytes.readUint32(cargo, 4)
        if cargo.count > 8 {
            remaining = cargo.subdata(in: 8 ..< cargo.count)
        } else {
            remaining = Data()
        }
    }

    public init(codeA: UInt32, codeB: UInt32, remaining: Data = Data([0, 0, 0])) {
        cargo = Bytes.combine(
            Bytes.toUint32(codeA),
            Bytes.toUint32(codeB),
            remaining
        )
        self.codeA = codeA
        self.codeB = codeB
        self.remaining = remaining
    }

    /// Malfunction code pairs that should be ignored (not treated as actual malfunctions).
    public static let IGNORABLE_CODES: [(UInt32, UInt32)] = [
        (0, 0), // empty
        (3, 8230), // 3-0x2026
        (18, 8311), // 18-0x2077
        (26, 8322) // 26-0x2082
    ]

    /// Formatted malfunction code string if present.
    public var errorString: String {
        if !hasMalfunction() { return "" }
        return String(format: "%d-%#x", codeA, codeB)
    }

    /// Whether the pump reports a malfunction. Optionally suppresses malfunctions when
    /// other notification payloads contain matching IDs.
    public func hasMalfunction(_ otherMessages: [NotificationMessage] = []) -> Bool {
        for code in Self.IGNORABLE_CODES {
            if code.0 == codeA, code.1 == codeB {
                return false
            }
        }

        if matchesKnownIds(otherMessages) {
            return false
        }

        return true
    }

    private func matchesKnownIds(_ otherMessages: [NotificationMessage]) -> Bool {
        for message in otherMessages {
            if message.notificationIds.contains(Int(codeA)) {
                return true
            }
        }
        return false
    }

    public var notificationCount: Int {
        (hasMalfunction() && !errorString.isEmpty) ? 1 : 0
    }

    public var notificationIds: Set<Int> {
        hasMalfunction() ? [Int(codeA)] : []
    }

    public var id: Int { Int(codeA) }

    public var notificationDescription: String? { errorString }

    public var description: String {
        "MalfunctionStatusResponse(cargo=\(cargo.hexadecimalString), codeA=\(codeA), codeB=\(codeB), remaining=\(remaining.hexadecimalString))"
    }
}
