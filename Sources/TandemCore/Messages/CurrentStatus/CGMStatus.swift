import Foundation

/// Request Dexcom CGM session status from the pump.
public class CGMStatusRequest: Message {
    public static let props = MessageProps(
        opCode: 80,
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
}

/// Response with details about the current CGM session.
public class CGMStatusResponse: Message {
    public static let props = MessageProps(
        opCode: 81,
        size: 10,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var sessionStateId: Int
    public var lastCalibrationTimestamp: UInt32
    public var sensorStartedTimestamp: UInt32
    public var transmitterBatteryStatusId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        sessionStateId = Int(cargo[0])
        lastCalibrationTimestamp = Bytes.readUint32(cargo, 1)
        sensorStartedTimestamp = Bytes.readUint32(cargo, 5)
        transmitterBatteryStatusId = Int(cargo[9])
    }

    public init(
        sessionStateId: Int,
        lastCalibrationTimestamp: UInt32,
        sensorStartedTimestamp: UInt32,
        transmitterBatteryStatusId: Int
    ) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(sessionStateId),
            Bytes.toUint32(lastCalibrationTimestamp),
            Bytes.toUint32(sensorStartedTimestamp),
            Bytes.firstByteLittleEndian(transmitterBatteryStatusId)
        )
        self.sessionStateId = sessionStateId
        self.lastCalibrationTimestamp = lastCalibrationTimestamp
        self.sensorStartedTimestamp = sensorStartedTimestamp
        self.transmitterBatteryStatusId = transmitterBatteryStatusId
    }

    public var sessionState: SessionState? {
        SessionState(rawValue: sessionStateId)
    }

    public var transmitterBatteryStatus: TransmitterBatteryStatus? {
        TransmitterBatteryStatus(rawValue: transmitterBatteryStatusId)
    }

    public var lastCalibrationDate: Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(lastCalibrationTimestamp))
    }

    public var sensorStartedDate: Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(sensorStartedTimestamp))
    }

    public enum SessionState: Int {
        case sessionStopped = 0
        case sessionStartPending = 1
        case sessionActive = 2
        case sessionStopPending = 3
    }

    public enum TransmitterBatteryStatus: Int {
        case unavailable = 0
        case error = 1
        case expired = 2
        case ok = 3
        case outOfRange = 4
    }
}
