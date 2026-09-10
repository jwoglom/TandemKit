@testable import TandemKit
import XCTest

/// The pump's fixed delivery characteristics, which dose bookkeeping and the reported dose window
/// both derive from. Both rates are confirmed against pump logs, so they are pinned exactly.
final class TandemPumpCapabilitiesTests: XCTestCase {
    func testBolusDurationUsesTheNominalRate() {
        XCTAssertEqual(
            TandemPumpCapabilities.estimatedBolusDuration(toDeliver: 1.0),
            28.745858684009523,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            TandemPumpCapabilities.estimatedBolusDuration(toDeliver: 0.3),
            0.3 / TandemPumpCapabilities.bolusSpeedUnder10U,
            accuracy: 1e-9
        )
    }

    /// Deliveries of 10 U and over run at the faster rate, so the threshold has to be pinned: a
    /// 10 U bolus must not be given the slow rate's ~5-minute window.
    func testDeliveryRateSwitchesAtTenUnits() {
        XCTAssertEqual(
            TandemPumpCapabilities.estimatedBolusDuration(toDeliver: 10.0),
            112.00233479381131,
            accuracy: 1e-9
        )
        XCTAssertLessThan(
            TandemPumpCapabilities.estimatedBolusDuration(toDeliver: 10.0),
            TandemPumpCapabilities.estimatedBolusDuration(toDeliver: 9.99)
        )
    }

    /// The lead-in the pump spends accepting a request before insulin moves.
    func testBolusInitiationDelayIsFifteenSeconds() {
        XCTAssertEqual(TandemPumpCapabilities.bolusInitiationDelay, 15)
    }

    func testSupportedBasalRatesCoverTheDeliverableRange() {
        let rates = TandemPumpCapabilities.supportedBasalRates
        XCTAssertEqual(rates.first, 0.0)
        XCTAssertEqual(rates.last, 15.0)
        XCTAssertFalse(rates.contains(where: { $0 > 0 && $0 < 0.1 }))
    }
}
