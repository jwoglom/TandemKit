import XCTest
@testable import TandemCore

final class RemoteCarbEntryRequestTests: XCTestCase {
    func testOpcodeNegative14Request_ID10677() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461710145)
        let expected = RemoteCarbEntryRequest(carbs: 5, pumpTime: 1200239, bolusId: 10677)

        let parsed: RemoteCarbEntryRequest = MessageTester.test(
            "02aaf2aa210500016f501200b5294123851bf324",
            -86,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01aaa4f96f10fe37167c6d90d2802fda729c1e0e",
            "00aa0288"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testOpcodeNegative14Request_ID10678() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461710202)
        let expected = RemoteCarbEntryRequest(carbs: 3, pumpTime: 1200239, bolusId: 10678)

        let parsed: RemoteCarbEntryRequest = MessageTester.test(
            "02cff2cf210300016f501200b6297a23851bc88f",
            -49,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01cfdcc573801e4a91567fe0219a9275211f7f17",
            "00cfa162"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testRemoteCarbEntryRequest_ID10653_011u_11g_carbs_161mgdl_013u_iob() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461589420)
        let expected = RemoteCarbEntryRequest(carbs: 11, pumpTime: 1079469, bolusId: 10653)

        let parsed: RemoteCarbEntryRequest = MessageTester.test(
            "0238f238210b0001ad7810009d29ac4b831b5e16",
            56,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "013890d5f066c547ed4e3e883476f805abc0ddf9",
            "00383346"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
