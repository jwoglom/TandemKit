@testable import TandemCore
import XCTest

final class RemoteBgEntryRequestTests: XCTestCase {
    func testRemoteBgEntryRequest_ID10676() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_710_145)
        let expected = RemoteBgEntryRequest(
            bg: 180,
            useForCgmCalibration: false,
            isAutopopBg: true,
            pumpTime: 1_200_173,
            bolusId: 10676
        )

        let parsed: RemoteBgEntryRequest = MessageTester.test(
            "023bb63b23b4000000012d501200b4290023851b",
            59,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "013b1f62ef2f006c8a8ea7aeb9203fa4b7eaebd2",
            "003bc0b6800c"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testRemoteBgEntryRequest_ID10677() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_710_145)
        let expected = RemoteBgEntryRequest(
            bg: 185,
            useForCgmCalibration: false,
            isAutopopBg: true,
            pumpTime: 1_200_239,
            bolusId: 10677
        )

        let parsed: RemoteBgEntryRequest = MessageTester.test(
            "02a9b6a923b9000000016f501200b5294123851b",
            -87,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01a93ade55510ac65b57f647a1899c0a6e4e94bc",
            "00a9d8306d38"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testRemoteBgEntryRequest_ID10678() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_710_202)
        let expected = RemoteBgEntryRequest(
            bg: 186,
            useForCgmCalibration: false,
            isAutopopBg: true,
            pumpTime: 1_200_239,
            bolusId: 10678
        )

        let parsed: RemoteBgEntryRequest = MessageTester.test(
            "02ceb6ce23ba000000016f501200b6297a23851b",
            -50,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01ceb50b6d51ca170c5ecf018b37a14a4a05c412",
            "00ceda1ff8b1"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testRemoteBgEntryRequest_ID10652() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_589_158)
        let expected = RemoteBgEntryRequest(
            bg: 142,
            useForCgmCalibration: false,
            isAutopopBg: true,
            pumpTime: 1_079_274,
            bolusId: 10652
        )

        let parsed: RemoteBgEntryRequest = MessageTester.test(
            "023cb63c238e00000001ea7710009c29bc4a831b",
            60,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "013c1d2edd239e1a8499a6686078565ad1b8acdc",
            "003ca71a3107"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testRemoteBgEntryRequest_G7Calibrate_169mgdl() {
        MessageTester.initPumpState("", 0)
        let expected = RemoteBgEntryRequest(
            bg: 169,
            useForCgmCalibration: true,
            isAutopopBg: true,
            pumpTime: 2_887_044,
            bolusId: 0
        )

        let parsed: RemoteBgEntryRequest = MessageTester.test(
            "02d6b6d623a900010001840d2c00000052cf5a20",
            -42,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01d6e4b43557b2ab113cb54266a2d1616c1972f8",
            "00d66e6d6786"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testRemoteBgEntryRequest_G7Calibrate_170mgdl() {
        MessageTester.initPumpState("", 0)
        let expected = RemoteBgEntryRequest(
            bg: 170,
            useForCgmCalibration: true,
            isAutopopBg: true,
            pumpTime: 2_887_044,
            bolusId: 0
        )

        let parsed: RemoteBgEntryRequest = MessageTester.test(
            "02e1b6e123aa00010001840d2c00000082cf5a20",
            -31,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01e10d94486401b99108897a2c3fdb9c2ec6be15",
            "00e1663cfd1a"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
