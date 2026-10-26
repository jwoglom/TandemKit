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

    private final class CompletionRecorder: CompletionDelegate {
        let done: XCTestExpectation

        init(_ done: XCTestExpectation) {
            self.done = done
        }

        func completionNotifyingDidComplete(_: CompletionNotifying) {
            done.fulfill()
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

    func testRemovingThePumpTellsTheHostTheFlowIsDoneAfterTheHostHasLetTheFlowGo() {
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth())
        let delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = DispatchQueue(label: "remove-pump-test")
        let recorder = CompletionRecorder(expectation(description: "the host is told the flow is done"))
        var coordinator: TandemUICoordinator? = TandemUICoordinator(pumpManager: manager, colorPalette: palette, allowDebugFeatures: false)
        coordinator?.completionDelegate = recorder
        // What viewWillAppear shows a manager the host already has.
        coordinator?.screenStack = [.pumpSettings]

        coordinator?.stepFinished()
        // Trio's sheet drops the flow as soon as its pump manager is nil.
        coordinator = nil

        wait(for: [recorder.done], timeout: 5)
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

    func testPairingAsksAboutPumpHistoryBeforeTheHostHasTheManager() {
        let coordinator = makeSetupCoordinator()
        let host = OnboardingHost()
        coordinator.pumpManagerOnboardingDelegate = host
        coordinator.pumpManager.state.featureFlags[.historyBackfill] = true
        coordinator.pumpManager.state.featureFlags[.historyDoseReporting] = true

        coordinator.pairingFinished()

        XCTAssertEqual(coordinator.screenStack, [.loadHistory])
        XCTAssertTrue(host.calls.isEmpty)
        XCTAssertTrue(coordinator.ownsPumpManager)
    }

    func testWithoutHistoryDoseReportingPairingHandsTheManagerOverAtOnce() {
        let coordinator = makeSetupCoordinator()
        let host = OnboardingHost()
        coordinator.pumpManagerOnboardingDelegate = host
        coordinator.pumpManager.state.featureFlags[.historyDoseReporting] = false

        coordinator.pairingFinished()

        XCTAssertEqual(coordinator.screenStack, [.setupComplete])
        XCTAssertEqual(host.calls, ["created", "onboarded"])
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
            coordinator.beginAppearanceTransition(true, animated: false)
            coordinator.endAppearanceTransition()
        }

        XCTAssertNil(freed)
    }
}
