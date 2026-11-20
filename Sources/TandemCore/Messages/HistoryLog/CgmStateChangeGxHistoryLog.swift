import Foundation

/// One step of the pump's Dexcom CGM (G6 and G7) session state machine (jwoglom/pumpX2#146). Provisional names.
/// `stateId` matches CgmStatusV2Response `sessionStateId`; it is not Control-IQ's CGM availability.
public class CgmStateChangeGxHistoryLog: HistoryLog {
    public static let typeId = 219

    public let previousStateId: Int
    public let stateId: Int
    public let eventId: Int
    public let unknown11: Int
    public let unknown15: Int
    public let unknown18: UInt32
    public let unknown23: Int

    /// 3 is rare and unidentified, so it maps to `.unknown`.
    public enum State: Int {
        case stopped = 0
        case startPending = 1
        case active = 2
        case unknown = -1
    }

    public enum Event: Int {
        /// Once per 5-minute transmitter cycle, 0-5 s before `dataReceived`; also starts a session.
        case cycleStart = 1
        /// The CGM reading record, when there is one, follows in the same second.
        case dataReceived = 2
        /// 27 s after `cycleStart` when no reading arrives.
        case noData = 3
        case sessionCommand = 4
        /// Follows a pump-button release or (Mobi) a signed control request within 10 s.
        case userActivity = 5
        /// Every 300 s with no CGM session.
        case idleTick = 6
        case unknown = -1
    }

    public var previousState: State {
        State(rawValue: previousStateId) ?? .unknown
    }

    public var state: State {
        State(rawValue: stateId) ?? .unknown
    }

    public var event: Event {
        Event(rawValue: eventId) ?? .unknown
    }

    public var isStateChange: Bool {
        previousStateId != stateId
    }

    public required init(cargo: Data) {
        let raw = HistoryLog.fillCargo(cargo)
        let word10 = Bytes.readUint32(raw, 10)
        let word14 = Bytes.readUint32(raw, 14)
        let word22 = Bytes.readUint32(raw, 22)
        previousStateId = Int(word10 & 0xFF)
        unknown11 = Int(word10 >> 8)
        stateId = Int(word14 & 0xFF)
        unknown15 = Int(word14 >> 8)
        unknown18 = Bytes.readUint32(raw, 18)
        eventId = Int(word22 & 0xFF)
        unknown23 = Int(word22 >> 8)
        super.init(cargo: raw)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, previousStateId: Int, stateId: Int, eventId: Int, unknown11: Int = 0, unknown15: Int = 0, unknown18: UInt32 = 0, unknown23: Int = 0) {
        let payload = CgmStateChangeGxHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            previousStateId: previousStateId,
            stateId: stateId,
            eventId: eventId,
            unknown11: unknown11,
            unknown15: unknown15,
            unknown18: unknown18,
            unknown23: unknown23
        )
        self.previousStateId = previousStateId
        self.stateId = stateId
        self.eventId = eventId
        self.unknown11 = unknown11
        self.unknown15 = unknown15
        self.unknown18 = unknown18
        self.unknown23 = unknown23
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, previousStateId: Int, stateId: Int, eventId: Int, unknown11: Int = 0, unknown15: Int = 0, unknown18: UInt32 = 0, unknown23: Int = 0) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(UInt32(previousStateId & 0xFF) | UInt32(truncatingIfNeeded: unknown11 << 8)),
                Bytes.toUint32(UInt32(stateId & 0xFF) | UInt32(truncatingIfNeeded: unknown15 << 8)),
                Bytes.toUint32(unknown18),
                Bytes.toUint32(UInt32(eventId & 0xFF) | UInt32(truncatingIfNeeded: unknown23 << 8))
            )
        )
    }

    override public var description: String {
        "CgmStateChangeGxHistoryLog(cargo=\(cargo.hexadecimalString), previousStateId=\(previousStateId), stateId=\(stateId), eventId=\(eventId), unknown11=\(unknown11), unknown15=\(unknown15), unknown18=\(unknown18), unknown23=\(unknown23))"
    }
}
