import LoopKitUI
import TandemKit

public class TandemKitPlugin: NSObject, PumpManagerUIPlugin {
    public var pumpManagerType: (any PumpManagerUI.Type)? {
        return TandemPumpManager.self
    }
}
