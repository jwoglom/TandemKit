import Foundation

public struct BluetoothUUID: Hashable, Sendable {
    public let uuid: UUID

    public init(uuid: UUID) {
        self.uuid = uuid
    }

    public init(uuidString: String) {
        self.uuid = UUID(uuidString: uuidString)!
    }

    public var uuidString: String { uuid.uuidString }
}
