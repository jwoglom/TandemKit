import CoreBluetooth

/// Enum counterpart to `CharacteristicUUID` providing type safety
/// similar to `Characteristic` in pumpx2.
enum Characteristic {
    case currentStatus
    case historyLog
    case authorization
    case control
    case controlStream

    var uuid: CBUUID {
        switch self {
        case .currentStatus:
            return CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS.cbUUID
        case .historyLog:
            return CharacteristicUUID.HISTORY_LOG_CHARACTERISTICS.cbUUID
        case .authorization:
            return CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS.cbUUID
        case .control:
            return CharacteristicUUID.CONTROL_CHARACTERISTICS.cbUUID
        case .controlStream:
            return CharacteristicUUID.CONTROL_STREAM_CHARACTERISTICS.cbUUID
        }
    }

    /// Returns the matching Characteristic enum for the given UUID if known.
    static func of(uuid: CBUUID) -> Characteristic? {
        switch uuid {
        case CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS.cbUUID:
            return .currentStatus
        case CharacteristicUUID.HISTORY_LOG_CHARACTERISTICS.cbUUID:
            return .historyLog
        case CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS.cbUUID:
            return .authorization
        case CharacteristicUUID.CONTROL_CHARACTERISTICS.cbUUID:
            return .control
        case CharacteristicUUID.CONTROL_STREAM_CHARACTERISTICS.cbUUID:
            return .controlStream
        default:
            return nil
        }
    }
}
