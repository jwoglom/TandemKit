import Combine
import Foundation
import LoopKit

class TandemKitPumpInformationViewModel: ObservableObject {
    @Published var apiVersion: String = ""
    @Published var serialNumber: String = ""
    @Published var pumpSerial: String = ""
    @Published var softwareName: String = ""
    @Published var controlBitsA: String = ""
    @Published var controlBitsB: String = ""
    @Published var pcbSerialNumber: String = ""

    private let pumpManager: TandemPumpManager
    let openDebug: () -> Void
    let allowDebugFeatures: Bool

    init(
        pumpManager: TandemPumpManager,
        openDebug: @escaping () -> Void = {},
        allowDebugFeatures: Bool = false
    ) {
        self.pumpManager = pumpManager
        self.openDebug = openDebug
        self.allowDebugFeatures = allowDebugFeatures

        self.pumpManager(pumpManager, didUpdate: pumpManager.status, oldStatus: pumpManager.status)
        self.pumpManager.addStatusObserver(self, queue: DispatchQueue.main)
    }
}

extension TandemKitPumpInformationViewModel: PumpManagerStatusObserver {
    func pumpManager(_: any LoopKit.PumpManager, didUpdate _: LoopKit.PumpManagerStatus, oldStatus _: LoopKit.PumpManagerStatus) {
        let pumpState = self.pumpManager.state.pumpState
        DispatchQueue.main.async {
            let modelNumber = (pumpState.modelNumber?.formatted(.number.grouping(.never)) ?? "")
            let pcbsn = "#" + (pumpState.pcbSerialNumber?.formatted(.number.grouping(.never)) ?? "")
            
            self.serialNumber = "#" + (pumpState.pumpSerial?.formatted(.number.grouping(.never)) ?? "")
            self.pumpSerial = self.serialNumber + ", " + modelNumber
            self.pcbSerialNumber = pcbsn + ", " + modelNumber
            self.apiVersion = (pumpState.apiVersion ?? KnownApiVersion.apiV2_1.value).description
            self.softwareName = pumpState.softwareName ?? ""
            self.controlBitsA = pumpState.controlBitsA?.hexadecimalString ?? ""
            self.controlBitsB = pumpState.controlBitsB?.hexadecimalString ?? ""
        }
    }
}
