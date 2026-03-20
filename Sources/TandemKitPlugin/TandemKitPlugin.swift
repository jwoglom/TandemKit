import LoopKitUI
import TandemKit

public class TandemKitPlugin: NSObject, PumpManagerUIPlugin {
    public override init() {
        super.init()
    }

    public var pumpManagerType: (any PumpManagerUI.Type)? {
        TandemPumpManager.self
    }
}
