import Foundation
#if canImport(os)
    import os.log
#endif
import LoopKit
import LoopKitUI
import TandemCore
import TandemKit

@available(macOS 13.0, iOS 14.0, *) public final class TandemKitPlugin: NSObject, PumpManagerUIPlugin {
    private let log = OSLog(category: "TandemKitPlugin")

    public var pumpManagerType: (any PumpManagerUI.Type)? {
        if #available(macOS 13.0, iOS 14.0, *) {
            return TandemPumpManager.self
        }
        return nil
    }

    public var cgmManagerType: (any CGMManagerUI.Type)? {
        nil
    }

    override public init() {
        super.init()
        log.default("TandemKitPlugin instantiated")
    }
}
