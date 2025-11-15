import CoreBluetooth

enum PeripheralManagerError: Error {
    case cbPeripheralError(Error)
    case notReady
    case busy
    case timeout([PeripheralManager.CommandCondition])
    case emptyValue
    case unknownCharacteristic(CBUUID)
    case unknownService(CBUUID)
}

extension PeripheralManagerError {
    public var errorDescription: String? {
        switch self {
        case let .cbPeripheralError(error):
            return error.localizedDescription
        case .notReady:
            return "Not connected"
        case .busy:
            return "Busy"
        case .timeout:
            return "Timeout"
        case .emptyValue:
            return "Characteristic value was empty"
        case let .unknownCharacteristic(cbuuid):
            return String(format: "Unknown characteristic: %@", cbuuid.uuidString)
        case let .unknownService(cbuuid):
            return String(format: "Unknown service: %@", cbuuid.uuidString)
        }
    }
}
