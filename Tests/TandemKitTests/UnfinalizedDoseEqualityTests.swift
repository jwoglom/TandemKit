import Foundation
import LoopKit
@testable import TandemKit
import XCTest

final class UnfinalizedDoseEqualityTests: XCTestCase {
    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private static let nonState: Set<String> = ["logger"]

    func testFullyPopulatedDoseEqualsASeparatelyBuiltCopy() {
        let dose = Self.populatedDose()
        let copy = Self.populatedDose()

        XCTAssertEqual(copy, dose)
    }

    func testRawValueRoundTripRestoresAnEqualDose() throws {
        let dose = Self.populatedDose()

        XCTAssertEqual(try XCTUnwrap(UnfinalizedDose(rawValue: dose.rawValue)), dose)
    }

    func testChangingAnyStoredPropertyMakesTheDosesUnequal() throws {
        let raw = Self.populatedDose().rawValue
        let base = try XCTUnwrap(UnfinalizedDose(rawValue: raw))

        for (name, mutate) in Self.mutations {
            var changedRaw = raw
            mutate(&changedRaw)
            let changed = try XCTUnwrap(UnfinalizedDose(rawValue: changedRaw), name)
            XCTAssertFalse(changed == base, "Changing \(name) left the doses equal")
        }
    }

    func testEveryStoredPropertyHasAMutation() {
        let stored = Set(Mirror(reflecting: Self.populatedDose()).storedPropertyNames).subtracting(Self.nonState)
        let mutated = Set(Self.mutations.map(\.name))

        XCTAssertEqual(stored.subtracting(mutated).sorted(), [], "Add a mutation for each, and compare it in ==")
        XCTAssertEqual(mutated.subtracting(stored).sorted(), [], "Mutations naming no stored property")
    }

    // Half the stored properties are `let`, so a mutation edits the raw value both doses are decoded from.
    private static var mutations: [(name: String, mutate: (inout UnfinalizedDose.RawValue) -> Void)] {
        [
            ("bolusId", { $0["bolusId"] = 2005 }),
            ("tempRateId", { $0["tempRateId"] = nil }),
            ("tempPercent", { $0["tempPercent"] = nil }),
            ("eventRaw", { $0["eventRaw"] = nil }),
            ("type", { $0["type"] = DoseType.tempBasal.rawValue }),
            ("startDate", { $0["startDate"] = t0.addingTimeInterval(1) }),
            ("deliveryStartDate", { $0["deliveryStartDate"] = nil }),
            ("estimatedEndDate", { $0["estimatedEndDate"] = t0.addingTimeInterval(.minutes(5)) }),
            ("value", { $0["value"] = 2.5 }),
            ("deliveredUnits", { $0["deliveredUnits"] = 1.2 }),
            ("insulinType", { $0["insulinType"] = InsulinType.humalog.rawValue }),
            ("automatic", { $0["automatic"] = false }),
            ("isUnconfirmed", { $0["isUnconfirmed"] = true })
        ]
    }

    private static func populatedDose() -> UnfinalizedDose {
        let dose = UnfinalizedDose(
            units: 2.4,
            duration: .seconds(120),
            activationType: .automatic,
            insulinType: .novolog,
            bolusId: 2004,
            now: t0
        )
        dose.tempRateId = 17
        dose.tempPercent = 150
        dose.eventRaw = Data([0x01, 0x02, 0x40, 0xE2, 0x01, 0x00, 0x11, 0x00, 0x00, 0x00])
        dose.recordDeliveryStart(t0.addingTimeInterval(4), now: t0.addingTimeInterval(10))
        dose.deliveredUnits = 1.1
        return dose
    }
}
