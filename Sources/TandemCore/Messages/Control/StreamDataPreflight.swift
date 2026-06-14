import Foundation

/// Request for stream data preflight check.
public class StreamDataPreflightRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-126)),
        size: 0,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .apiFuture
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "StreamDataPreflightRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response to a stream data preflight request.
///
/// Cargo layout (3 bytes):
///   [0] status       uint8 - 0=ACK/success
///   [1] statusTypeId uint8 - PreflightStatusType ordinal
///   [2] streamTypeId uint8 - PreflightStreamType ordinal
public class StreamDataPreflightResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-125)),
        size: 3,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .apiFuture
    )

    public var cargo: Data
    public var status: Int
    public var statusTypeId: Int
    public var streamTypeId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        status = Int(cargo[0])
        statusTypeId = Int(cargo[1])
        streamTypeId = Int(cargo[2])
    }

    public init(status: Int, statusTypeId: Int, streamTypeId: Int) {
        cargo = StreamDataPreflightResponse.buildCargo(status: status, statusTypeId: statusTypeId, streamTypeId: streamTypeId)
        self.status = status
        self.statusTypeId = statusTypeId
        self.streamTypeId = streamTypeId
    }

    public static func buildCargo(status: Int, statusTypeId: Int, streamTypeId: Int) -> Data {
        Bytes.combine(
            Data([UInt8(status & 0xFF)]),
            Data([UInt8(statusTypeId & 0xFF)]),
            Data([UInt8(streamTypeId & 0xFF)])
        )
    }

    public enum PreflightStatusType: Int {
        case success = 0
        case sensorContextTooBig = 1
        case anotherCgmActive = 2
        case incompatibleSensor = 3
        case invalidSensorContext = 4
        case invalidPumpTime = 5
        case pumpIsBusy = 6
        case sensorHasAlreadyBeenUsed = 7
        case internalError = 8
        case engineeringUseOnly = 9
        case timeout = 10
        case sensorUnavailable = 11
        case invalidSensorTimeParams = 12
        case unknown = 13
    }

    public enum PreflightStreamType: Int {
        case freestyleLibre2 = 0
        case unknown = 1
    }

    public var statusType: PreflightStatusType? { PreflightStatusType(rawValue: statusTypeId) }
    public var streamType: PreflightStreamType? { PreflightStreamType(rawValue: streamTypeId) }

    public var description: String {
        "StreamDataPreflightResponse(cargo=\(cargo.hexadecimalString), status=\(status), statusTypeId=\(statusTypeId), streamTypeId=\(streamTypeId))"
    }
}
