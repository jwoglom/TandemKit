@testable import TandemKit
import XCTest

/// The volumes and rates the host offers and rounds its requests to before they reach the pump.
@available(macOS 13.0, iOS 14.0, *) final class SupportedDeliveryIncrementsTests: XCTestCase {
    private var manager: TandemPumpManager!

    override func setUp() {
        super.setUp()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth())
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    func testBolusVolumesRunFromAFiftiethTo25UnitsInFiftieths() {
        let volumes = manager.supportedBolusVolumes

        XCTAssertEqual(volumes.count, 500)
        XCTAssertEqual(volumes.first, 0.05)
        XCTAssertEqual(volumes.last, 25.0)
        XCTAssertEqual(manager.supportedMaximumBolusVolumes, volumes)
    }

    /// A table built by adding 0.05 to a Double drifts off the literals a host compares against.
    func testBolusVolumesHoldTheExactLiterals() {
        for literal in [0.05, 0.15, 0.35, 0.6, 1.0, 2.35, 9.95, 24.95] {
            XCTAssertTrue(manager.supportedBolusVolumes.contains(literal), "\(literal)")
        }
    }

    func testBasalRatesAreTheCapabilityTable() {
        XCTAssertEqual(manager.supportedBasalRates, TandemPumpCapabilities.supportedBasalRates)
    }

    func testBolusVolumesRoundDownToTheGrid() {
        XCTAssertEqual(manager.roundToSupportedBolusVolume(units: 1.0), 1.0)
        XCTAssertEqual(manager.roundToSupportedBolusVolume(units: 2.35), 2.35)
        XCTAssertEqual(manager.roundToSupportedBolusVolume(units: 1.04), 1.0, "down, not to the nearer 1.05")
        XCTAssertEqual(manager.roundToSupportedBolusVolume(units: 0.1 + 0.2), 0.3)
        XCTAssertEqual(manager.roundToSupportedBolusVolume(units: 30), 25.0)
    }

    func testBolusVolumesBelowTheSmallestRoundToZero() {
        for units in [0.0, 0.049, -1.0] {
            XCTAssertEqual(manager.roundToSupportedBolusVolume(units: units), 0, "\(units)")
        }
    }

    func testBasalRatesRoundDownToTheGrid() {
        XCTAssertEqual(manager.roundToSupportedBasalRate(unitsPerHour: 0.1), 0.1)
        XCTAssertEqual(manager.roundToSupportedBasalRate(unitsPerHour: 1.26), 1.26)
        XCTAssertEqual(manager.roundToSupportedBasalRate(unitsPerHour: 0.159), 0.15, "down, not to the nearer 0.16")
        XCTAssertEqual(manager.roundToSupportedBasalRate(unitsPerHour: 20), 15.0)
    }

    /// The pump runs no rate between 0 and 0.1 U/hr, so a request there becomes a zero temp.
    func testBasalRatesBelowTheMinimumRoundToZero() {
        for rate in [0.0, 0.05, 0.099, -1.0] {
            XCTAssertEqual(manager.roundToSupportedBasalRate(unitsPerHour: rate), 0, "\(rate)")
        }
    }
}
