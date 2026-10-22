import LoopKit
import LoopKitUI
import SwiftUI
@testable import TandemKit
import UIKit
import XCTest

/// Who owns the pump manager a setup flow creates, and when the host is handed it (#603).
@available(macOS 13.0, iOS 14.0, *) final class TandemUICoordinatorOnboardingTests: XCTestCase {
    private final class OnboardingHost: PumpManagerOnboardingDelegate {
        var calls: [String] = []

        func pumpManagerOnboarding(didCreatePumpManager _: PumpManagerUI) {
            calls.append("created")
        }

        func pumpManagerOnboarding(didOnboardPumpManager _: PumpManagerUI) {
            calls.append("onboarded")
        }

        func pumpManagerOnboarding(didPauseOnboarding _: PumpManagerUI) {
            calls.append("paused")
        }
    }

    private let palette = LoopUIColorPalette(
        guidanceColors: GuidanceColors(),
        carbTintColor: .green,
        glucoseTintColor: .blue,
        insulinTintColor: .orange,
        loopStatusColorPalette: StateColorPalette(unknown: .gray, normal: .green, warning: .yellow, error: .red),
        chartColorPalette: ChartColorPalette(
            axisLine: .gray,
            axisLabel: .gray,
            grid: .gray,
            glucoseTint: .blue,
            insulinTint: .orange,
            carbTint: .green
        )
    )

    private func makeSetupCoordinator() -> TandemUICoordinator {
        TandemUICoordinator(colorPalette: palette, allowDebugFeatures: false)
    }

    private func transport(of manager: TandemPumpManager) -> TandemBluetoothManager? {
        manager.bluetooth as? TandemBluetoothManager
    }

    func testASetupFlowOwnsTheManagerItCreates() {
        XCTAssertTrue(makeSetupCoordinator().ownsPumpManager)
    }

    func testAFlowForAnExistingManagerNeverOwnsIt() {
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth())

        let coordinator = TandemUICoordinator(pumpManager: manager, colorPalette: palette, allowDebugFeatures: false)

        XCTAssertFalse(coordinator.ownsPumpManager)
    }

    func testPairingHandsTheManagerToTheHostCreatedThenOnboarded() {
        let coordinator = makeSetupCoordinator()
        let host = OnboardingHost()
        coordinator.pumpManagerOnboardingDelegate = host

        coordinator.handPumpManagerToHost()

        XCTAssertEqual(host.calls, ["created", "onboarded"])
        XCTAssertTrue(coordinator.pumpManager.state.onboarded)
        XCTAssertFalse(coordinator.ownsPumpManager)
    }

    func testAFlowThatGoesAwayStillOwningItsManagerTakesItsTransportDown() {
        let manager: TandemPumpManager = autoreleasepool {
            let coordinator = makeSetupCoordinator()
            XCTAssertEqual(transport(of: coordinator.pumpManager)?.isActive, true)
            return coordinator.pumpManager
        }

        XCTAssertEqual(transport(of: manager)?.isActive, false)
    }

    func testAFlowThatGoesAwayAfterHandingItsManagerOverLeavesItRunning() {
        let manager: TandemPumpManager = autoreleasepool {
            let coordinator = makeSetupCoordinator()
            coordinator.handPumpManagerToHost()
            return coordinator.pumpManager
        }

        XCTAssertEqual(transport(of: manager)?.isActive, true)
    }

    /// Its screens' closures held the flow, and the flow its screens, so a dismissed flow lived on.
    func testAFlowShownOnceIsFreedWhenNothingHoldsIt() {
        weak var freed: TandemUICoordinator?

        autoreleasepool {
            let coordinator = makeSetupCoordinator()
            freed = coordinator
            coordinator.loadViewIfNeeded()
            coordinator.viewWillAppear(false)
        }

        XCTAssertNil(freed)
    }
}
