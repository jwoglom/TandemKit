// Minimal stubs to allow building on platforms without LoopKit.

import Foundation

public protocol PumpManagerDelegate: AnyObject {}

public protocol PumpManager {
    associatedtype RawStateValue
    var rawState: RawStateValue { get }
}

public protocol PumpManagerUI: PumpManager {
    static var localizedTitle: String { get }
    static var managerIdentifier: String { get }
}

public protocol CGMManagerUI {}
