import Foundation
import LoopKit

public protocol PumpManagerUIPlugin {
    init()

    var pumpManagerType: (any PumpManagerUI.Type)? { get }
    var cgmManagerType: (any CGMManagerUI.Type)? { get }
}
