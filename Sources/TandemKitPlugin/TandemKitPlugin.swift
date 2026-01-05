import Foundation
import LoopKit
import LoopKitUI
import TandemCore
import TandemKit

@available(macOS 13.0, iOS 14.0, *) public final class TandemKitPlugin: NSObject, PumpManagerUIPlugin {
    private let log = TandemLogger(category: "TandemKitPlugin")

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
        log.info("TandemKitPlugin instantiated")
    }
}
