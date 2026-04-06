import Foundation

public class HighestAamRequest: Message {
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
        "HighestAamRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response with the highest-priority active alarm/malfunction code pair.
public class HighestAamResponse: Message, NotificationMessage, NotificationEnum {
    public static let props = MessageProps(
        opCode: 121,
        size: 11,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        variableSize: true
    )

    public var cargo: Data
    public var aamId: UInt32
    public var faultId: UInt32
    public var remaining: Data

    public required init(cargo: Data) {
        self.cargo = cargo
        aamId = Bytes.readUint32(cargo, 0)
        faultId = Bytes.readUint32(cargo, 4)
        remaining = cargo.count > 8 ? cargo.subdata(in: 8 ..< cargo.count) : Data()
    }

    public init(aamId: UInt32, faultId: UInt32, remaining: Data = Data()) {
        cargo = Bytes.combine(
            Bytes.toUint32(aamId),
            Bytes.toUint32(faultId),
            remaining
        )
        self.aamId = aamId
        self.faultId = faultId
        self.remaining = remaining
    }

    /// Malfunction code pairs that should be ignored (not treated as actual malfunctions).
    public static let IGNORABLE_CODES: [(UInt32, UInt32)] = [
        (0, 0), // empty
        (3, 8230), // 3-0x2026
        (18, 8311), // 18-0x2077
        (26, 8322) // 26-0x2082
    ]

    /// Formatted malfunction code string if this is a real malfunction.
    public var errorString: String {
        guard hasMalfunction() else { return "" }
        return String(format: "%d-0x%x", aamId, faultId)
    }

    /// Whether this represents a genuine malfunction. Optionally suppresses codes that
    /// match IDs in concurrently active notification messages (e.g. alarm/alert responses).
    public func hasMalfunction(_ otherMessages: [NotificationMessage] = []) -> Bool {
        for code in Self.IGNORABLE_CODES {
            if code.0 == aamId, code.1 == faultId {
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
            if message.notificationIds.contains(Int(aamId)) {
                return true
            }
        }
        return false
    }

    public var notificationCount: Int {
        (hasMalfunction() && !errorString.isEmpty) ? 1 : 0
    }

    public var notificationIds: Set<Int> {
        hasMalfunction() ? [Int(aamId)] : []
    }

    public var id: Int { Int(aamId) }

    public var notificationDescription: String? { errorString }

    /// Cross-references with ActiveAamBits and MalfunctionBitmaskStatus to confirm
    /// whether the reported malfunction is genuine.
    public func matchesActiveMalfunction(
        activeMalfunctionBits: ActiveAamBitsResponse?,
        malfunctionBitmaskStatusResponse: MalfunctionBitmaskStatusResponse?
    ) -> Bool {
        if let bits = activeMalfunctionBits,
           bits.aamType == .malfunction
        {
            return bits.hasActiveBit(Int(aamId))
        }

        if let malfStatus = malfunctionBitmaskStatusResponse {
            return malfStatus.hasMalfunctionBit(Int(aamId))
        }

        return true
    }

    public var description: String {
        "HighestAamResponse(cargo=\(cargo.hexadecimalString), aamId=\(aamId), faultId=\(faultId), remaining=\(remaining.hexadecimalString))"
    }
}
