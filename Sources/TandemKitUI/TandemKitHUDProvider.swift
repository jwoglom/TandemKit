import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

internal class TandemKitHUDProvider: NSObject, HUDProvider {
    var managerIdentifier: String {
        TandemPumpManager.managerIdentifier
    }

    private let pumpManager: TandemPumpManager

    private var reservoirView: TandemKitReservoirView?

    private let bluetoothProvider: BluetoothProvider

    private let colorPalette: LoopUIColorPalette

    private var refreshTimer: Timer?

    private let allowedInsulinTypes: [InsulinType]

    var visible: Bool = true {
        didSet {
            if oldValue != visible, visible {
                hudDidAppear()
            }
        }
    }

    public init(
        pumpManager: TandemPumpManager,
        bluetoothProvider: BluetoothProvider,
        colorPalette: LoopUIColorPalette,
        allowedInsulinTypes: [InsulinType]
    ) {
        self.pumpManager = pumpManager
        self.bluetoothProvider = bluetoothProvider
        self.colorPalette = colorPalette
        self.allowedInsulinTypes = allowedInsulinTypes
        super.init()
        self.pumpManager.addStatusObserver(self, queue: .main)
    }

    public func createHUDView() -> BaseHUDView? {
        reservoirView = TandemKitReservoirView.instantiate()
        updateReservoirView()

        return reservoirView
    }

    public var hudViewRawState: HUDProvider.HUDViewRawState {
        var rawValue: HUDProvider.HUDViewRawState = [:]

        rawValue["lastStatusDate"] = pumpManager.rawState["lastStatusDate"]
        rawValue["reservoirLevel"] = pumpManager.rawState["reservoirLevel"]

        return rawValue
    }

    public func didTapOnHUDView(_: BaseHUDView, allowDebugFeatures _: Bool) -> HUDTapAction? {
        nil
    }

    private func hudDidAppear() {
        updateReservoirView()
        pumpManager.ensureCurrentPumpData { _ in
            DispatchQueue.main.async {
                self.updateReservoirView()
            }
        }
    }

    public static func createHUDView(rawValue: HUDProvider.HUDViewRawState) -> BaseHUDView? {
        let reservoirView: TandemKitReservoirView?

        if let lastStatusDate = rawValue["lastStatusDate"] as? Date {
            reservoirView = TandemKitReservoirView.instantiate()
            reservoirView!.update(level: rawValue["reservoirLevel"] as? Double, at: lastStatusDate)
        } else {
            reservoirView = nil
        }

        return reservoirView
    }

    private func updateReservoirView() {
        guard let reservoirView = reservoirView,
              let reservoir = pumpManager.reservoirLevel
        else {
            return
        }

        reservoirView.update(level: reservoir.unitVolume, at: reservoir.startDate)
    }
}

extension TandemKitHUDProvider: PumpManagerStatusObserver {
    func pumpManager(_: any LoopKit.PumpManager, didUpdate _: LoopKit.PumpManagerStatus, oldStatus _: LoopKit.PumpManagerStatus) {
        DispatchQueue.main.async {
            self.updateReservoirView()
        }
    }
}
