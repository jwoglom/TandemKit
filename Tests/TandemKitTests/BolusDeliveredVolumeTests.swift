import LoopKit
@testable import TandemKit
import XCTest

/// The pump takes and reports bolus volumes in milliunits, and a partial delivery (e.g. 1041 mU) has
/// to reach the host at that resolution — flooring to the 0.05 U command grid understates IOB. Pins
/// `queryLastBolusDeliveredVolume`, both paths that use it, and the volume `enactBolus` sends.
@available(macOS 13.0, iOS 14.0, *) final class BolusDeliveredVolumeTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    private static let bolusId = 2004

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "bolus-delivered-volume-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
    }

    override func tearDown() {
        delegateQueue = nil
        delegate = nil
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func stubLastBolus(deliveredVolume: UInt32, bolusId: Int = bolusId) {
        bluetooth.stub(LastBolusStatusRequest.self, with: LastBolusStatusResponse(
            status: 0,
            bolusId: bolusId,
            timestamp: 0,
            deliveredVolume: deliveredVolume,
            bolusStatusId: 0,
            bolusSourceId: 0,
            bolusTypeBitmask: 0,
            extendedBolusDuration: 0
        ))
    }

    /// Runs a bolus far enough that the driver is tracking it, which is what both paths read.
    private func startBolus(units: Double) {
        bluetooth.stub(BolusPermissionRequest.self, with: BolusPermissionResponse(
            status: 0,
            bolusId: Self.bolusId,
            nackReasonId: 0
        ))
        bluetooth.stub(InitiateBolusRequest.self, with: InitiateBolusResponse(
            status: 0,
            bolusId: Self.bolusId,
            statusTypeId: 0
        ))

        let enacted = expectation(description: "enactBolus")
        manager.enactBolus(decisionId: nil, units: units, activationType: .manualNoRecommendation) { error in
            XCTAssertNil(error)
            enacted.fulfill()
        }
        wait(for: [enacted], timeout: 5.0)
        delegateQueue.sync {}
        XCTAssertEqual(manager.state.bolusDose?.bolusId, Self.bolusId)
    }

    private func initiateBolusRequests(enacting amounts: [Double]) -> [InitiateBolusRequest] {
        bluetooth.stub(BolusPermissionRequest.self, with: BolusPermissionResponse(
            status: 0,
            bolusId: Self.bolusId,
            nackReasonId: 0
        ))
        // Refused, so no bolus is left in flight to refuse the next amount.
        bluetooth.stub(InitiateBolusRequest.self, with: InitiateBolusResponse(
            status: 1,
            bolusId: Self.bolusId,
            statusTypeId: 0
        ))
        bluetooth.stub(BolusPermissionReleaseRequest.self, with: BolusPermissionReleaseResponse(status: 0))

        for units in amounts {
            let enacted = expectation(description: "enactBolus \(units) U")
            manager.enactBolus(decisionId: nil, units: units, activationType: .manualNoRecommendation) { _ in enacted.fulfill() }
            wait(for: [enacted], timeout: 5.0)
        }
        return bluetooth.sent(InitiateBolusRequest.self)
    }

    /// The delivered volume of the last finalized (immutable) bolus the host was told about.
    private func lastFinalizedBolusDeliveredUnits() -> Double? {
        delegateQueue.sync {}
        return delegate.pumpEvents
            .compactMap(\.dose)
            .last { $0.type == .bolus && !$0.isMutable }?
            .deliveredUnits
    }

    // MARK: - Reporting resolution

    func testDeliveredVolumeKeepsThePumpsMilliunitResolution() throws {
        for (milliunits, expected) in [
            (UInt32(1041), 1.041),
            (UInt32(1049), 1.049),
            (UInt32(25), 0.025),
            (UInt32(1000), 1.0),
            (UInt32(0), 0.0)
        ] {
            stubLastBolus(deliveredVolume: milliunits)
            let delivered = try XCTUnwrap(manager.queryLastBolusDeliveredVolume(bolusId: Self.bolusId))
            XCTAssertEqual(
                delivered,
                expected,
                accuracy: 1e-9,
                "\(milliunits) mU must be reported as \(expected) U"
            )
        }
    }

    /// `roundToSupportedBolusVolume` would turn a 1.049 U delivery into 1.00 U.
    func testDeliveredVolumeIsNotFlooredToTheCommandGrid() throws {
        stubLastBolus(deliveredVolume: 1049)

        let delivered = try XCTUnwrap(manager.queryLastBolusDeliveredVolume(bolusId: Self.bolusId))

        XCTAssertEqual(manager.roundToSupportedBolusVolume(units: 1.049), 1.00, accuracy: 1e-9)
        XCTAssertGreaterThan(delivered, 1.04)
    }

    /// The live and history paths report the same quantity, so they must round it the same way.
    func testDeliveredVolumeMatchesTheHistoryMappersRounding() throws {
        stubLastBolus(deliveredVolume: 1041)

        let delivered = try XCTUnwrap(manager.queryLastBolusDeliveredVolume(bolusId: Self.bolusId))

        XCTAssertEqual(delivered, TandemPumpCapabilities.roundToReportingResolution(1.041), accuracy: 1e-12)
    }

    func testDeliveredVolumeIsNilWhenThePumpReportsADifferentBolus() {
        stubLastBolus(deliveredVolume: 1041, bolusId: Self.bolusId + 1)
        XCTAssertNil(manager.queryLastBolusDeliveredVolume(bolusId: Self.bolusId))
    }

    func testDeliveredVolumeIsNilWhenThePumpDoesNotAnswer() {
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        XCTAssertNil(manager.queryLastBolusDeliveredVolume(bolusId: Self.bolusId))
    }

    // MARK: - Finalization paths

    func testCancelledBolusReportsThePumpsPartialDeliveryUnfloored() {
        startBolus(units: 2.0)
        stubLastBolus(deliveredVolume: 1041)
        bluetooth.stub(CancelBolusRequest.self, with: CancelBolusResponse(
            statusId: 0,
            bolusId: Self.bolusId,
            reasonId: 0
        ))

        let cancelled = expectation(description: "cancelBolus")
        manager.cancelBolus { result in
            if case .failure(let error) = result {
                XCTFail("cancelBolus failed: \(error)")
            }
            cancelled.fulfill()
        }
        // The cancel path sleeps ~2s to let the pump store the bolus before reading it back.
        wait(for: [cancelled], timeout: 15.0)

        XCTAssertEqual(lastFinalizedBolusDeliveredUnits(), 1.041)
    }

    func testNaturallyCompletedBolusReportsThePumpsDeliveredVolumeUnfloored() {
        startBolus(units: 2.0)
        stubLastBolus(deliveredVolume: 1949)
        // bolusId 0 with no delivery in progress is how the pump says the bolus is over.
        bluetooth.stub(CurrentBolusStatusRequest.self, with: CurrentBolusStatusResponse(
            statusId: 0,
            bolusId: 0,
            timestamp: 0,
            requestedVolume: 2000,
            bolusSourceId: 0,
            bolusTypeBitmask: 0
        ))

        manager.fetchBolusStatus(fromSync: false)

        XCTAssertEqual(lastFinalizedBolusDeliveredUnits(), 1.949)
        XCTAssertNil(manager.state.bolusDose)
    }

    // MARK: - Commanded volume

    func testABolusOffTheCommandGridIsSentInExactMilliunits() {
        startBolus(units: 0.13)

        let sent = bluetooth.sent(InitiateBolusRequest.self)
        XCTAssertEqual(sent.map(\.totalVolume), [130])
        XCTAssertEqual(sent.map(\.foodVolume), [130])
        XCTAssertEqual(sent.map(\.correctionVolume), [0])
    }

    func testEverySupportedBolusVolumeIsSentAsItsExactMilliunits() {
        let volumes = manager.supportedBolusVolumes

        let sent = initiateBolusRequests(enacting: volumes)

        XCTAssertEqual(sent.count, volumes.count)
        for (index, (units, request)) in zip(volumes, sent).enumerated() {
            let milliunits = UInt32(50 * (index + 1))
            XCTAssertEqual(request.totalVolume, milliunits, "\(units) U")
            XCTAssertEqual(request.foodVolume, milliunits, "\(units) U")
        }
    }

    func testAVolumeJustUnderAMilliunitInBinaryIsSentAsThatMilliunit() {
        let volumes: [(units: Double, milliunits: UInt32)] = [
            (2.01, 2010),
            (4.02, 4020),
            (8.03, 8030),
            (16.06, 16060),
            (16.15, 16150),
            (1.001, 1001),
            (2.002, 2002)
        ]

        let sent = initiateBolusRequests(enacting: volumes.map(\.units))

        XCTAssertEqual(sent.count, volumes.count)
        for ((units, milliunits), request) in zip(volumes, sent) {
            XCTAssertLessThan(units * 1000, Double(milliunits))
            XCTAssertEqual(request.totalVolume, milliunits, "\(units) U")
            XCTAssertEqual(request.foodVolume, milliunits, "\(units) U")
        }
    }
}
