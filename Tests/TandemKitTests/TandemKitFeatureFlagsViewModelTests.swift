@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemKitFeatureFlagsViewModelTests: XCTestCase {
    /// The screen hides the flag list behind a triple tap unless a flag is off its default, so a
    /// choice the user made can never be left unreachable.
    func testTheFlagListIsShownWithoutTheTripleTapOnceAFlagIsOn() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )

        XCTAssertFalse(TandemKitFeatureFlagsViewModel(pumpManager: manager).hasFlagOffItsDefault)

        manager.setFeatureFlag(.controlIQSupport, enabled: true)

        XCTAssertTrue(TandemKitFeatureFlagsViewModel(pumpManager: manager).hasFlagOffItsDefault)
    }

    func testTheFlagListIsShownWithoutTheTripleTapOnceADefaultOnFlagIsTurnedOff() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )

        manager.setFeatureFlag(.historyBackfill, enabled: false)

        XCTAssertTrue(TandemKitFeatureFlagsViewModel(pumpManager: manager).hasFlagOffItsDefault)
    }

    func testTheFlagsScreenWritesThroughToTheManager() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )
        let viewModel = TandemKitFeatureFlagsViewModel(pumpManager: manager)

        viewModel.setFlag(.quickBolusButtonSupport, enabled: true)

        XCTAssertTrue(viewModel.isEnabled(.quickBolusButtonSupport))
        XCTAssertTrue(manager.state.featureFlags.quickBolusButtonSupport)
    }
}
