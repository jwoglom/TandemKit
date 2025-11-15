import XCTest
@testable import TandemCore

final class BolusCalcDataSnapshotRequestTests: XCTestCase {
    func testBolusCalcDataSnapshotRequest() {
        let expected = BolusCalcDataSnapshotRequest()

        let parsed: BolusCalcDataSnapshotRequest = MessageTester.test(
            "0003720300a72f",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
