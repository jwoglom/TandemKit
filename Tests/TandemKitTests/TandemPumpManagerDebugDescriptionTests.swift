import Foundation
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerDebugDescriptionTests: XCTestCase {
    private func makeState() -> TandemPumpManagerState {
        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState = PumpState(
            peripheralUuid: "peripheral",
            derivedSecret: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            serverNonce: Data([0xCA, 0xFE, 0xBA, 0xBE]),
            apiVersion: ApiVersion(major: 3, minor: 8),
            pumpSerial: 1_234_567,
            pumpModel: .MOBI
        )
        state.pumpState.pincode = "246802"
        state.lastReconciliation = Date(timeIntervalSinceReferenceDate: 987_654)
        state.latestInsulinOnBoard = 1.5
        state.historyBackfill = HistoryBackfillState(pumpSerial: 1_234_567, watermark: 42)
        state.bolusDose = UnfinalizedDose(
            units: 2,
            duration: 60,
            activationType: .manualNoRecommendation,
            insulinType: nil,
            bolusId: 7
        )
        state.controlIQUserMode = .sleep
        return state
    }

    func testStateDescriptionNamesEveryStoredProperty() {
        let state = makeState()
        let description = state.debugDescription
        for label in Mirror(reflecting: state).children.compactMap(\.label) {
            XCTAssertTrue(description.contains("\n* \(label):"), "\(label) is missing from the state's debugDescription")
        }
        for label in Mirror(reflecting: state.pumpState).children.compactMap(\.label) {
            XCTAssertTrue(description.contains("\n  * \(label):"), "\(label) is missing from the pump state's fields")
        }
    }

    func testStateDescriptionLeavesOutThePairingSecrets() {
        let description = makeState().debugDescription

        XCTAssertFalse(description.contains("246802"))
        XCTAssertFalse(description.contains(Data([0xDE, 0xAD, 0xBE, 0xEF]).base64EncodedString()))
        XCTAssertFalse(description.contains(Data([0xCA, 0xFE, 0xBA, 0xBE]).base64EncodedString()))
        XCTAssertTrue(description.contains("* derivedSecret: present"))
    }

    func testStateDescriptionPrintsValuesWithoutOptionalWrappersOrModuleNames() {
        let description = makeState().debugDescription

        XCTAssertFalse(description.contains("Optional("))
        XCTAssertFalse(description.contains("TandemKit."))
        XCTAssertTrue(description.contains("* apiVersion: 3.8"))
        XCTAssertTrue(description.contains("* pumpModel: MOBI"))
        XCTAssertTrue(description.contains("* controlIQUserMode: sleep"))
    }

    func testManagerDescriptionUsesTheStateDescription() {
        let description = TandemPumpManager(state: makeState(), bluetooth: StubPumpBluetooth()).debugDescription

        XCTAssertTrue(description.hasPrefix("## TandemPumpManager\n"))
        XCTAssertTrue(description.contains("\n### TandemPumpManagerState\n"))
        XCTAssertFalse(description.contains("TandemPumpManagerState("))
    }
}
