import Foundation
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemKitPumpProfileViewerViewModelTests: XCTestCase {
    private typealias ViewModel = TandemKitPumpProfileViewerViewModel

    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        StubIDPPump([.init(startTime: 0, basalRate: 800), .init(startTime: 360, basalRate: 1000)], idpId: 4)
            .install(on: bluetooth)
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    private func readToCompletion(_ viewModel: ViewModel) {
        viewModel.readIfNeeded()
        let deadline = Date().addingTimeInterval(1)
        while viewModel.readout == nil || viewModel.isReading, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    func testOpeningTheScreenListsTheStatusThenEachProfileWithItsSettingsAndSegments() {
        let viewModel = ViewModel(pumpManager: manager)

        readToCompletion(viewModel)

        XCTAssertNotNil(viewModel.statusRow?.exchange.response as? ProfileStatusResponse)
        XCTAssertEqual(viewModel.profileSections.map(\.title), ["IDP 4: Test (active)"])
        XCTAssertEqual(viewModel.profileSections.first?.rows.map(\.title), ["Settings", "Segment 0 (active)", "Segment 1"])
        XCTAssertNil(viewModel.readout?.failure)
    }

    func testReopeningTheScreenDoesNotReadAgain() {
        let viewModel = ViewModel(pumpManager: manager)
        readToCompletion(viewModel)
        bluetooth.resetRecordedTraffic()

        viewModel.readIfNeeded()

        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }

    func testTheExportIsTheReadoutAsJSON() throws {
        let viewModel = ViewModel(pumpManager: manager)
        XCTAssertNil(viewModel.exportFileURL())
        readToCompletion(viewModel)

        let url = try XCTUnwrap(viewModel.exportFileURL())
        defer { try? FileManager.default.removeItem(at: url) }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])

        XCTAssertEqual(url.pathExtension, "json")
        XCTAssertEqual((json["profiles"] as? [[String: Any]])?.first?["idpId"] as? Int, 4)
    }

    func testWithoutAPumpTheScreenSaysSo() {
        let viewModel = ViewModel(pumpManager: nil)

        viewModel.read()

        XCTAssertEqual(viewModel.readout?.failure, "Pump not available")
        XCTAssertFalse(viewModel.isReading)
    }
}
