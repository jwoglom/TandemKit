import Foundation
#if canImport(os)
import os.log
#endif
import LoopKit
import LoopKitUI
import TandemCore
import TandemKit

public final class TandemKitPlugin: NSObject, PumpManagerUIPlugin {
    private let log = OSLog(category: "TandemKitPlugin")

    public var pumpManagerType: (any PumpManagerUI.Type)? {
        TandemPumpManager.self
    }

    public var cgmManagerType: (any CGMManagerUI.Type)? {
        nil
    }

    public override init() {
        super.init()
        log.default("TandemKitPlugin instantiated")
    }
}
