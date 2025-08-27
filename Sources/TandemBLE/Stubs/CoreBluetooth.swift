#if canImport(CoreBluetooth)
import CoreBluetooth
#else
import Foundation

public struct CBUUID: Hashable {
    public let uuidString: String
    public init(string: String) {
        self.uuidString = string
    }
}

#endif
