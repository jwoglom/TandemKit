import LoopKit
import SwiftUI

class TandemKitPumpInformationViewModel: ObservableObject {
    @Published var apiVersion: String = ""
    @Published var pumpSerial: String = ""
    @Published var softwareName: String = ""

    private let pumpManager: TandemPumpManager
    init(pumpManager: TandemPumpManager) {
        self.pumpManager = pumpManager

        self.pumpManager(pumpManager, didUpdate: pumpManager.status, oldStatus: pumpManager.status)
    }
}

extension TandemKitPumpInformationViewModel: PumpManagerStatusObserver {
    func pumpManager(_: any LoopKit.PumpManager, didUpdate _: LoopKit.PumpManagerStatus, oldStatus _: LoopKit.PumpManagerStatus) {
        DispatchQueue.main.async {
            self.pumpSerial = self.pumpManager.state.pumpState.pumpSerial?.formatted() ?? ""
            self.apiVersion = (self.pumpManager.state.pumpState.apiVersion ?? KnownApiVersion.apiV2_1.value).description
            self.softwareName = self.pumpManager.state.pumpState.softwareName ?? ""
        }
    }
}
