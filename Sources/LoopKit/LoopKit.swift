// Minimal stubs to allow building on platforms without LoopKit.

import Foundation
#if canImport(UIKit)
import UIKit
#endif

public protocol PumpManagerDelegate: AnyObject {}

public protocol PumpManager {
    associatedtype RawStateValue
    var rawState: RawStateValue { get }
}

public protocol PumpManagerUI: PumpManager {
    static var localizedTitle: String { get }
    static var managerIdentifier: String { get }
#if canImport(UIKit)
    func pairingViewController(onFinished: @escaping (Result<Void, Error>) -> Void) -> UIViewController
#endif
}

public protocol CGMManagerUI {}
