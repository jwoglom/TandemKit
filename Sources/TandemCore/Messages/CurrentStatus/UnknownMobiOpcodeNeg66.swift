import Foundation

/// Request CGM status for Mobi pumps (V2).
public class CGMStatusV2Request: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-66)),
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "CGMStatusV2Request(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response with CGM session status for Mobi pumps.
///
/// Binary layout (20 bytes):
///   offset 0  (1 byte):  sessionStateId
///   offset 1  (4 bytes): lastCalibrationTimestamp (uint32 LE, pump epoch seconds)
///   offset 5  (4 bytes): sensorStartedTimestamp (uint32 LE, pump epoch seconds)
///   offset 9  (1 byte):  transmitterBatteryStatusId
///   offset 10 (4 bytes): sessionDurationSeconds (uint32 LE)
///   offset 14 (4 bytes): sessionTimeRemainingSeconds (uint32 LE)
///   offset 18 (1 byte):  cgmSensorTypeId
///   offset 19 (1 byte):  gracePeriod (nonzero = true)
public class CGMStatusV2Response: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-65)),
        size: 20,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var sessionStateId: Int
    public var lastCalibrationTimestamp: UInt32
    public var sensorStartedTimestamp: UInt32
    public var transmitterBatteryStatusId: Int
    public var sessionDurationSeconds: UInt32
    public var sessionTimeRemainingSeconds: UInt32
    public var cgmSensorTypeId: Int
    public var gracePeriod: Bool

    public required init(cargo: Data) {
        self.cargo = cargo
        sessionStateId = Int(cargo[0])
        lastCalibrationTimestamp = Bytes.readUint32(cargo, 1)
        sensorStartedTimestamp = Bytes.readUint32(cargo, 5)
        transmitterBatteryStatusId = Int(cargo[9])
        sessionDurationSeconds = Bytes.readUint32(cargo, 10)
        sessionTimeRemainingSeconds = Bytes.readUint32(cargo, 14)
        cgmSensorTypeId = Int(cargo[18])
        gracePeriod = cargo[19] != 0
    }

    public init(
        sessionStateId: Int,
        lastCalibrationTimestamp: UInt32,
        sensorStartedTimestamp: UInt32,
        transmitterBatteryStatusId: Int,
        sessionDurationSeconds: UInt32,
        sessionTimeRemainingSeconds: UInt32,
        cgmSensorTypeId: Int,
        gracePeriod: Bool
    ) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(sessionStateId),
            Bytes.toUint32(lastCalibrationTimestamp),
            Bytes.toUint32(sensorStartedTimestamp),
            Bytes.firstByteLittleEndian(transmitterBatteryStatusId),
            Bytes.toUint32(sessionDurationSeconds),
            Bytes.toUint32(sessionTimeRemainingSeconds),
            Bytes.firstByteLittleEndian(cgmSensorTypeId),
            Data([gracePeriod ? 1 : 0])
        )
        self.sessionStateId = sessionStateId
        self.lastCalibrationTimestamp = lastCalibrationTimestamp
        self.sensorStartedTimestamp = sensorStartedTimestamp
        self.transmitterBatteryStatusId = transmitterBatteryStatusId
        self.sessionDurationSeconds = sessionDurationSeconds
        self.sessionTimeRemainingSeconds = sessionTimeRemainingSeconds
        self.cgmSensorTypeId = cgmSensorTypeId
        self.gracePeriod = gracePeriod
    }

    public var sessionState: SessionState {
        SessionState(rawValue: sessionStateId) ?? .unknown
    }

    public var transmitterBatteryStatus: TransmitterBatteryStatus {
        TransmitterBatteryStatus(rawValue: transmitterBatteryStatusId) ?? .unknown
    }

    public var cgmSensorType: CGMSensorType {
        CGMSensorType(rawValue: cgmSensorTypeId) ?? .unknown
    }

    public var lastCalibrationDate: Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(lastCalibrationTimestamp))
    }

    public var sensorStartedDate: Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(sensorStartedTimestamp))
    }

    /// CGM session states matching the Tandem app's CGMStatusBState enum ordinals.
    public enum SessionState: Int {
        case stopped = 0
        case startPending = 1
        case active = 2
        case stopPending = 3
        case unknown = 4
    }

    /// Transmitter battery status ordinals matching the Tandem app's enum.
    public enum TransmitterBatteryStatus: Int {
        case unavailable = 0
        case error = 1
        case expired = 2
        case okay = 3
        case outOfRange = 4
        case unknown = 5
    }

    /// CGM sensor types matching the Tandem app's CGMSensorType enum ordinals.
    public enum CGMSensorType: Int {
        case notApplicable = 0
        case dexcomG6 = 1
        case fsl2 = 2
        case dexcomG7 = 3
        case unknown = 4
    }

    public var description: String {
        "CGMStatusV2Response(cargo=\(cargo.hexadecimalString), sessionState=\(sessionState), sessionStateId=\(sessionStateId), lastCalibrationTimestamp=\(lastCalibrationTimestamp), sensorStartedTimestamp=\(sensorStartedTimestamp), transmitterBatteryStatus=\(transmitterBatteryStatus), transmitterBatteryStatusId=\(transmitterBatteryStatusId), sessionDurationSeconds=\(sessionDurationSeconds), sessionTimeRemainingSeconds=\(sessionTimeRemainingSeconds), cgmSensorType=\(cgmSensorType), cgmSensorTypeId=\(cgmSensorTypeId), gracePeriod=\(gracePeriod))"
    }
}
