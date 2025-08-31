// Minimal stubs to allow building on platforms without LoopKit.

import Foundation

public protocol DeviceManager: AnyObject {}

public protocol PumpManager: DeviceManager {
    typealias RawStateValue = [String: Any]
    init?(rawState: RawStateValue)
    var rawState: RawStateValue { get }
}

public protocol PumpManagerDelegate: AnyObject {}

public class WeakSynchronizedDelegate<T> {
    public init() {}
    public var queue: DispatchQueue?
    public var delegate: T?
}

