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

    // MARK: - Milliunits

    /// Each product is a hair off its decimal value: 1.001 * 1000 is 1000.9999999999999.
    func testMilliunitsRoundsAwayDoubleNoise() {
        XCTAssertEqual(TandemPumpCapabilities.milliunits(1.001), 1001)
        XCTAssertEqual(Int(1.001 * 1000), 1000, "the truncation the helper exists to avoid")
        XCTAssertEqual(TandemPumpCapabilities.milliunits(0.119 * 100 / 100), 119)
        XCTAssertEqual(Int(0.119 * 100 / 100 * 1000), 118, "100% of a 0.119 U/hr profile, truncated")
        XCTAssertEqual(TandemPumpCapabilities.milliunits(0.57 + 0.01), 580)
        XCTAssertEqual(TandemPumpCapabilities.milliunits(1.1 * 0.4), 440)
        XCTAssertEqual(TandemPumpCapabilities.milliunits(0.58 * 50 / 100), 290)
        XCTAssertEqual(TandemPumpCapabilities.milliunits(Double(Float(0.9))), 900)
        XCTAssertEqual(TandemPumpCapabilities.milliunits(0.1 + 0.2), 300)
        XCTAssertEqual(TandemPumpCapabilities.milliunits(0), 0)
    }

    func testMilliunitsIsExactOnEveryGridRate() {
        for (index, rate) in TandemPumpCapabilities.supportedBasalRates.enumerated() where index > 0 {
            XCTAssertEqual(TandemPumpCapabilities.milliunits(rate), 90 + index * 10, "\(rate)")
        }
    }

    // MARK: - Grid flooring

    /// A value a hair under a grid step is that step; a hair over it is still that step.
    func testFloorOntoGridIsNotFooledByNoiseAroundAStep() {
        let grid = TandemPumpCapabilities.supportedBasalRates
        XCTAssertEqual(TandemPumpCapabilities.floor(0.57 + 0.01, ontoGrid: grid), 0.58)
        XCTAssertEqual(TandemPumpCapabilities.floor(0.58 - 1e-12, ontoGrid: grid), 0.58)
        XCTAssertEqual(TandemPumpCapabilities.floor(1.1 * 0.4, ontoGrid: grid), 0.44)
        XCTAssertEqual(TandemPumpCapabilities.floor(Double(Float(0.9)), ontoGrid: grid), 0.9)
        XCTAssertEqual(TandemPumpCapabilities.floor(0.1 + 0.2, ontoGrid: grid), 0.3)
    }

    func testFloorOntoGridFloorsWhatIsGenuinelyBetweenSteps() {
        let grid = TandemPumpCapabilities.supportedBasalRates
        XCTAssertEqual(TandemPumpCapabilities.floor(0.5849, ontoGrid: grid), 0.58)
        XCTAssertEqual(TandemPumpCapabilities.floor(0.0986, ontoGrid: grid), 0, "under the pump's lowest rate")
        XCTAssertEqual(TandemPumpCapabilities.floor(0.0995, ontoGrid: grid), 0, "half a milliunit is not a hair")
        XCTAssertEqual(TandemPumpCapabilities.floor(0.101 * 99 / 100, ontoGrid: grid), 0, "a hundredth of one is not either")
        XCTAssertEqual(TandemPumpCapabilities.floor(0.1596, ontoGrid: grid), 0.15)
        XCTAssertEqual(TandemPumpCapabilities.floor(0, ontoGrid: grid), 0)
        XCTAssertEqual(TandemPumpCapabilities.floor(-1, ontoGrid: grid), 0)
        XCTAssertEqual(TandemPumpCapabilities.floor(99, ontoGrid: grid), 15.0)
        XCTAssertEqual(TandemPumpCapabilities.floor(0.3, ontoGrid: [0.0, 0.05, 0.1]), 0.1)
        XCTAssertEqual(TandemPumpCapabilities.floor(0.3, ontoGrid: []), 0)
    }

    /// Every percent of every profile rate the pump can hold, against integer arithmetic: the grid
    /// rate is the floor of the exact share, however the Double product lands.
    func testEveryPercentOfEveryProfileRateFloorsAsIntegerArithmeticSays() {
        var baselines = Array(stride(from: 100, through: 3000, by: 1))
        baselines += stride(from: 3010, through: 15000, by: 10)
        var mismatches: [String] = []

        for baselineMilliunits in baselines {
            let baseline = Double(baselineMilliunits) / 1000
            for percent in 0 ... 250 {
                let rate = TandemPumpCapabilities.roundToSupportedBasalRate(baseline * Double(percent) / 100)
                let gridMilliunits = baselineMilliunits * percent / 1000 * 10
                let expected = gridMilliunits < 100 ? 0 : min(gridMilliunits, 15000)
                if TandemPumpCapabilities.milliunits(rate) != expected {
                    mismatches.append("\(percent)% of \(baseline) -> \(rate), expected \(expected) mU")
                }
            }
        }

        XCTAssertTrue(mismatches.isEmpty, "\(mismatches.count) mismatches, first: \(mismatches.prefix(5))")
    }

    func testSupportedBasalRatesStepByAHundredth() {
        let rates = TandemPumpCapabilities.supportedBasalRates
        XCTAssertEqual(rates.count, 1 + 1491)
        XCTAssertEqual(Array(rates.prefix(4)), [0.0, 0.1, 0.11, 0.12])
        for literal in [0.15, 0.29, 1.0, 1.26, 2.35, 14.99] {
            XCTAssertTrue(rates.contains(literal), "\(literal)")
        }
    }
}
