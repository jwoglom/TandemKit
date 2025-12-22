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
public class MalfunctionStatusResponse: Message {
    public static let props = MessageProps(
        opCode: 121,
        size: 11,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var codeA: UInt32
    public var codeB: UInt32
    public var remaining: Data

    public required init(cargo: Data) {
        self.cargo = cargo
        codeA = Bytes.readUint32(cargo, 0)
        codeB = Bytes.readUint32(cargo, 4)
        remaining = cargo.subdata(in: 8 ..< 11)
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
        (18, 8311) // 18-0x2077
    ]

    /// Formatted malfunction code string if present.
    public var errorString: String {
        if !hasMalfunction { return "" }
        return String(format: "%d-%#x", codeA, codeB)
    }

    /// Whether the pump reports a malfunction.
    public var hasMalfunction: Bool {
        for code in Self.IGNORABLE_CODES {
            if code.0 == codeA, code.1 == codeB {
                return false
            }
        }
        return true
    }
    public var description: String {
        "MalfunctionStatusResponse(cargo=\(cargo.hexadecimalString), codeA=\(codeA), codeB=\(codeB), remaining=\(remaining.hexadecimalString))"
    }
}
