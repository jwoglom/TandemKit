import Foundation
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemKitPumpInformationViewModelTests: XCTestCase {
    private typealias ViewModel = TandemKitPumpInformationViewModel

    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func seedPumpIdentity() {
        manager.state.pumpState = PumpState(
            apiVersion: ApiVersion(major: 3, minor: 5),
            pumpSerial: 1_234_567,
            modelNumber: 1_004_000,
            softwareName: "Control-IQ+ 7.9.0.2",
            controlBitsA: 0x1234_5678,
            controlBitsB: 0x9ABC_DEF0,
            pcbSerialNumber: 7_654_321
        )
    }

    /// Runs the main queue long enough for the view model's nested main-queue hops to land: a status
    /// update reaches it on the main queue, then schedules the reformat behind it.
    private func drainMainQueue(iterations: Int = 20) {
        for _ in 0 ..< iterations {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    // MARK: - Display

    func testThePumpsIdentityIsFormattedForDisplay() {
        seedPumpIdentity()

        let viewModel = ViewModel(pumpManager: manager)
        drainMainQueue()

        XCTAssertEqual(viewModel.apiVersion, "3.5")
        XCTAssertEqual(viewModel.serialNumber, "#1234567")
        XCTAssertEqual(viewModel.pumpSerial, "#1234567, 1004000")
        XCTAssertEqual(viewModel.pcbSerialNumber, "#7654321, 1004000")
        XCTAssertEqual(viewModel.softwareName, "Control-IQ+ 7.9.0.2")
        XCTAssertEqual(viewModel.controlBitsA, "0x12345678")
        XCTAssertEqual(viewModel.controlBitsB, "0x9abcdef0")
    }

    func testTheScreenPicksUpAnIdentityReadAfterItOpened() {
        let viewModel = ViewModel(pumpManager: manager)
        drainMainQueue()
        XCTAssertEqual(viewModel.softwareName, "")

        seedPumpIdentity()
        manager.notifyDelegateStateUpdated()
        drainMainQueue()

        XCTAssertEqual(viewModel.serialNumber, "#1234567")
        XCTAssertEqual(viewModel.apiVersion, "3.5")
        XCTAssertEqual(viewModel.softwareName, "Control-IQ+ 7.9.0.2")
    }

    // MARK: - Debug options

    func testDebugOptionsAreHiddenUnlessAllowed() {
        XCTAssertFalse(ViewModel(pumpManager: manager).allowDebugFeatures)

        var opened = false
        let viewModel = ViewModel(pumpManager: manager, openDebug: { opened = true }, allowDebugFeatures: true)
        viewModel.openDebug()

        XCTAssertTrue(viewModel.allowDebugFeatures)
        XCTAssertTrue(opened)
    }
}
