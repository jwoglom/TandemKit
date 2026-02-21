import LoopKitUI
import TandemKit

public class TandemKitPlugin: NSObject, PumpManagerUIPlugin {
    public var pumpManagerType: (any PumpManagerUI.Type)? {
        TandemPumpManager.self
    }
}
