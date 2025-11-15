import XCTest
@testable import TandemKit
@testable import TandemCore

final class TandemPumpManagerModelDetectionTests: XCTestCase {
    func testBluetoothIdentificationUpdatesStateAndStatus() throws {
        let manager = TandemPumpManager(state: TandemPumpManagerState())
        let pump = TandemPump(nil)

        manager.tandemPump(pump, didIdentifyPump: "Tandem Diabetes Care", model: "t:Mobi")

        XCTAssertEqual(manager.status.device?.manufacturer, "Tandem Diabetes Care")
        XCTAssertEqual(manager.status.device?.model, "t:Mobi")

        let restoredState = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.rawState))
        XCTAssertEqual(restoredState.detectedPumpInfo?.manufacturer, "Tandem Diabetes Care")
        XCTAssertEqual(restoredState.detectedPumpInfo?.model, "t:Mobi")
        XCTAssertEqual(restoredState.detectedPumpInfo?.identifier, .mobi)

        let roundTrippedManager = try XCTUnwrap(TandemPumpManager(rawState: manager.rawState))
        XCTAssertEqual(roundTrippedManager.status.device?.manufacturer, "Tandem Diabetes Care")
        XCTAssertEqual(roundTrippedManager.status.device?.model, "t:Mobi")
    }

    func testPumpVersionResponseInfersModelIdentifier() throws {
        let manager = TandemPumpManager(state: TandemPumpManagerState())
        let response = PumpVersionResponse(
            armSwVer: 0,
            mspSwVer: 0,
            configABits: 0,
            configBBits: 0,
            serialNum: 0,
            partNum: 0,
            pumpRev: "2.0",
            pcbaSN: 0,
            pcbaRev: "A",
            modelNum: 3
        )

        manager.pumpComm(PumpComm(pumpState: nil), didReceive: response, metadata: nil, characteristic: .CURRENT_STATUS_CHARACTERISTICS, txId: 0)

        XCTAssertEqual(manager.status.device?.model, KnownDeviceModel.mobi.displayName)
        XCTAssertEqual(manager.status.device?.manufacturer, "Tandem Diabetes Care")

        let restoredState = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.rawState))
        XCTAssertEqual(restoredState.detectedPumpInfo?.identifier, .mobi)
        XCTAssertEqual(restoredState.detectedPumpInfo?.model, KnownDeviceModel.mobi.displayName)
    }
}
