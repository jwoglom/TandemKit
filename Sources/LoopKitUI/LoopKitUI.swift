#if os(Linux)
import Foundation
import LoopKit

@available(macOS 13.0, iOS 14.0, *)
public protocol PumpManagerUIPlugin {
    init()

    var pumpManagerType: (any PumpManagerUI.Type)? { get }
    var cgmManagerType: (any CGMManagerUI.Type)? { get }
}
#else

@_exported import LoopKitUIBinary

#endif
