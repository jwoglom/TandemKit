import CoreBluetooth
import LoopKit
import SwiftUI
import TandemCore

class TandemKitSettingsViewModel: ObservableObject {
    private let log = PumpLogger(label: "TandemKitSettingsViewModel")
    private var pumpManager: TandemPumpManager?
    private var nextStep: () -> Void

    public var mirrorDetail: HomeScreenMirrorResponse?
    public var timeSinceReset: TimeSinceResetResponse?

    init(_ pumpManager: TandemPumpManager? = nil, nextStep: @escaping () -> Void) {
        self.pumpManager = pumpManager
        self.nextStep = nextStep

        self.pumpManager?.addStatusObserver(self, queue: .main)
    }

    var pumpState: PumpState? {
        pumpManager?.tandemPump.state
    }

    var pumpComm: PumpComm? {
        pumpManager?.tandemPump.pumpComm
    }

    func sendMessage(message: Message) -> Message? {
        guard let transport = pumpManager?.pairedTransport else {
            return nil
        }

        return try? transport.sendMessage(message)
    }

    deinit {
        pumpManager?.removeStatusObserver(self)
    }
}

extension TandemKitSettingsViewModel: PumpManagerStatusObserver {
    func pumpManager(
        _ loopkitPumpManager: any LoopKit.PumpManager,
        didUpdate _: LoopKit.PumpManagerStatus,
        oldStatus _: LoopKit.PumpManagerStatus
    ) {
        guard let pumpManager = loopkitPumpManager as? TandemPumpManager else {
            return
        }
    }
}
