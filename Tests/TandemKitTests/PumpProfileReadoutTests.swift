import Foundation
@testable import TandemKit
import XCTest

final class PumpProfileReadoutTests: XCTestCase {
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

    private func stubProfiles(segmentCounts: [Int: Int]) {
        let ids = segmentCounts.keys.sorted()
        let slot = { (index: Int) in index < ids.count ? ids[index] : 0 }
        bluetooth.stub(ProfileStatusRequest.self, with: ProfileStatusResponse(
            numberOfProfiles: ids.count,
            idpSlot0Id: slot(0),
            idpSlot1Id: slot(1),
            idpSlot2Id: slot(2),
            idpSlot3Id: slot(3),
            idpSlot4Id: slot(4),
            idpSlot5Id: slot(5),
            activeSegmentIndex: 0
        ))
        bluetooth.stub(IDPSettingsRequest.self) { request in
            let idpId = (request as! IDPSettingsRequest).idpId
            return IDPSettingsResponse(
                idpId: idpId,
                name: "Profile \(idpId)",
                numberOfProfileSegments: segmentCounts[idpId] ?? 0,
                insulinDuration: 300,
                maxBolus: 10000,
                carbEntry: true
            )
        }
        bluetooth.stub(IDPSegmentRequest.self) { request in
            let request = request as! IDPSegmentRequest
            return IDPSegmentResponse(
                idpId: request.idpId,
                segmentIndex: request.segmentIndex,
                profileStartTime: request.segmentIndex * 60,
                profileBasalRate: 800,
                profileCarbRatio: 10000,
                profileTargetBG: 110,
                profileISF: 50,
                idpStatusId: 31
            )
        }
    }

    private func read() -> PumpProfileReadout {
        var result: PumpProfileReadout?
        manager.readPumpProfiles { result = $0 }
        return result!
    }

    func testReadsSettingsForEachProfileAndEachOfItsSegments() {
        stubProfiles(segmentCounts: [3: 2, 7: 1])

        let readout = read()

        XCTAssertNil(readout.failure)
        XCTAssertEqual(readout.profiles.map(\.idpId), [3, 7])
        XCTAssertEqual(readout.profiles.map(\.segments.count), [2, 1])
        XCTAssertEqual(
            bluetooth.sentMessages.map { "\(PumpProfileReadout.messageName($0)) \($0.cargo.hexadecimalString)" },
            [
                "ProfileStatusRequest ",
                "IDPSettingsRequest 03",
                "IDPSegmentRequest 0300",
                "IDPSegmentRequest 0301",
                "IDPSettingsRequest 07",
                "IDPSegmentRequest 0700"
            ]
        )
    }

    func testAnUnansweredSegmentEndsTheReadAndKeepsWhatWasRead() {
        stubProfiles(segmentCounts: [3: 2, 7: 1])
        bluetooth.enqueue(IDPSegmentRequest.self, responses: [
            IDPSegmentResponse(
                idpId: 3,
                segmentIndex: 0,
                profileStartTime: 0,
                profileBasalRate: 800,
                profileCarbRatio: 10000,
                profileTargetBG: 110,
                profileISF: 50,
                idpStatusId: 31
            ),
            nil
        ])

        let readout = read()

        XCTAssertEqual(readout.failure, "No response to IDPSegmentRequest for IDP 3 segment 1")
        XCTAssertEqual(readout.profiles.count, 1)
        XCTAssertEqual(readout.profiles[0].segments.map { $0.response != nil }, [true, false])
        XCTAssertTrue(bluetooth.sent(IDPSettingsRequest.self).allSatisfy { $0.idpId == 3 })
    }

    func testAConnectionFailureSendsNothing() {
        bluetooth.connectError = PumpCommError.pumpNotConnected

        let readout = read()

        XCTAssertNil(readout.status)
        XCTAssertNotNil(readout.failure)
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }

    func testFieldsListStoredPropertiesInDeclarationOrderWithoutCargo() {
        let response = IDPSettingsResponse(
            idpId: 2,
            name: "Weekday",
            numberOfProfileSegments: 4,
            insulinDuration: 300,
            maxBolus: 10000,
            carbEntry: true
        )

        let fields = PumpProfileReadout.fields(of: response)

        XCTAssertEqual(fields.map(\.label), ["idpId", "name", "numberOfProfileSegments", "insulinDuration", "maxBolus", "carbEntry"])
        XCTAssertEqual(fields.map(\.value), ["2", "Weekday", "4", "300", "10000", "true"])
    }

    func testExportCarriesEveryRequestAndResponseWithCargoAndTypedFields() throws {
        stubProfiles(segmentCounts: [3: 1])

        let data = try XCTUnwrap(read().jsonData(exportedAt: Date(timeIntervalSince1970: 0)))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["complete"] as? Bool, true)
        let status = try XCTUnwrap(json["profileStatus"] as? [String: Any])
        let statusResponse = try XCTUnwrap(status["response"] as? [String: Any])
        XCTAssertEqual(statusResponse["name"] as? String, "ProfileStatusResponse")
        XCTAssertEqual(statusResponse["cargoHex"] as? String, "0103000000000000")

        let profiles = try XCTUnwrap(json["profiles"] as? [[String: Any]])
        let segments = try XCTUnwrap(profiles.first?["segments"] as? [[String: Any]])
        let segment = try XCTUnwrap(segments.first?["response"] as? [String: Any])
        let fields = try XCTUnwrap(segment["fields"] as? [String: Any])
        XCTAssertEqual(segment["opCode"] as? Int, 67)
        XCTAssertEqual(fields["profileCarbRatio"] as? Int, 10000)
        XCTAssertEqual(fields["profileBasalRate"] as? Int, 800)
        XCTAssertNil(fields["cargo"])
        let settings = try XCTUnwrap(profiles.first?["settings"] as? [String: Any])
        let settingsFields = try XCTUnwrap((settings["response"] as? [String: Any])?["fields"] as? [String: Any])
        XCTAssertEqual(settingsFields["carbEntry"] as? Bool, true)
        XCTAssertEqual(settingsFields["name"] as? String, "Profile 3")
    }
}
