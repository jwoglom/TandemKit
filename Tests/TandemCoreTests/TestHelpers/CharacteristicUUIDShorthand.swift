import CoreBluetooth
@testable import TandemKit

/// The message tests name pump characteristics with leading-dot shorthand
/// (`.CONTROL_CHARACTERISTICS`). The constants themselves live on
/// `CharacteristicUUID` and are typed `CBUUID`, so re-expose them on `CBUUID`
/// to make implicit member lookup resolve.
extension CBUUID {
    static let CURRENT_STATUS_CHARACTERISTICS = CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    static let QUALIFYING_EVENTS_CHARACTERISTICS = CharacteristicUUID.QUALIFYING_EVENTS_CHARACTERISTICS
    static let HISTORY_LOG_CHARACTERISTICS = CharacteristicUUID.HISTORY_LOG_CHARACTERISTICS
    static let AUTHORIZATION_CHARACTERISTICS = CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS
    static let CONTROL_CHARACTERISTICS = CharacteristicUUID.CONTROL_CHARACTERISTICS
    static let CONTROL_STREAM_CHARACTERISTICS = CharacteristicUUID.CONTROL_STREAM_CHARACTERISTICS
}
