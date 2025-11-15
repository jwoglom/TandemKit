@testable import TandemCore
import XCTest

final class InitiateBolusRequestTests: XCTestCase {
    func testInitiateBolusRequest_ID10650_1u() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_510_642)
        let expected = InitiateBolusRequest(
            totalVolume: 1000,
            bolusID: 10650,
            bolusTypeBitmask: 8,
            foodVolume: 0,
            correctionVolume: 0,
            bolusCarbs: 0,
            bolusBG: 0,
            bolusIOB: 0
        )

        let parsed: InitiateBolusRequest = MessageTester.test(
            "03399e393de80300009a29000008000000000000",
            57,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0239000000000000000000000000000000000000",
            "013900000000f217821b68f94cebe6717a5d1551",
            "003927147fec9ad979926aaccd74"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1000, Int(parsed.totalVolume))
        XCTAssertEqual(10650, parsed.bolusID)
        XCTAssertEqual(8, parsed.bolusTypeBitmask)
        XCTAssertEqual(Set([BolusType.food2]), parsed.bolusTypes)
        XCTAssertEqual(0, Int(parsed.foodVolume))
        XCTAssertEqual(0, Int(parsed.correctionVolume))
        XCTAssertEqual(0, parsed.bolusCarbs)
        XCTAssertEqual(0, parsed.bolusBG)
        XCTAssertEqual(0, Int(parsed.bolusIOB))
    }

    func testInitiateBolusRequest_ID10652_013u_13g_carbs_142mgdl() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_589_180)
        let expected = InitiateBolusRequest(
            totalVolume: 130,
            bolusID: 10652,
            bolusTypeBitmask: 1,
            foodVolume: 130,
            correctionVolume: 0,
            bolusCarbs: 13,
            bolusBG: 142,
            bolusIOB: 0
        )

        let parsed: InitiateBolusRequest = MessageTester.test(
            "033e9e3e3d820000009c29000001820000000000",
            62,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "023e00000d008e00000000000000000000000000",
            "013e00000000bc4a831b9cbf19ffb856288a8afa",
            "003e8f24a463e00cf3bbe5d305dd"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(130, Int(parsed.totalVolume))
        XCTAssertEqual(10652, parsed.bolusID)
        XCTAssertEqual(1, parsed.bolusTypeBitmask)
        XCTAssertEqual(Set([BolusType.food1]), parsed.bolusTypes)
        XCTAssertEqual(130, Int(parsed.foodVolume))
        XCTAssertEqual(0, Int(parsed.correctionVolume))
        XCTAssertEqual(13, parsed.bolusCarbs)
        XCTAssertEqual(142, parsed.bolusBG)
        XCTAssertEqual(0, Int(parsed.bolusIOB))
    }

    func testInitiateBolusRequest_ID10653_011u_11g_carbs_161mgdl_013u_iob() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_589_420)
        let expected = InitiateBolusRequest(
            totalVolume: 110,
            bolusID: 10653,
            bolusTypeBitmask: 1,
            foodVolume: 110,
            correctionVolume: 0,
            bolusCarbs: 11,
            bolusBG: 161,
            bolusIOB: 130
        )

        let parsed: InitiateBolusRequest = MessageTester.test(
            "03399e393d6e0000009d290000016e0000000000",
            57,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "023900000b00a100820000000000000000000000",
            "013900000000ac4b831b7a0b7cfc14a30b9c3995",
            "0039dc8bbbdfa2ce2ce995725407"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(110, Int(parsed.totalVolume))
        XCTAssertEqual(10653, parsed.bolusID)
        XCTAssertEqual(1, parsed.bolusTypeBitmask)
        XCTAssertEqual(Set([BolusType.food1]), parsed.bolusTypes)
        XCTAssertEqual(110, Int(parsed.foodVolume))
        XCTAssertEqual(0, Int(parsed.correctionVolume))
        XCTAssertEqual(11, parsed.bolusCarbs)
        XCTAssertEqual(161, parsed.bolusBG)
        XCTAssertEqual(130, Int(parsed.bolusIOB))
    }

    func testInitiateBolusRequest_ID10677() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_710_145)
        let expected = InitiateBolusRequest(
            totalVolume: 770,
            bolusID: 10677,
            bolusTypeBitmask: 3,
            foodVolume: 50,
            correctionVolume: 720,
            bolusCarbs: 5,
            bolusBG: 185,
            bolusIOB: 0
        )

        let parsed: InitiateBolusRequest = MessageTester.test(
            "03ab9eab3d02030000b52900000332000000d002",
            -85,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "02ab00000500b900000000000000000000000000",
            "01ab000000004123851bd5302d47de4038f56320",
            "00abce9113be8ce2a1e1b82126c5"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testInitiateBolusRequest_ID10678() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_710_202)
        let expected = InitiateBolusRequest(
            totalVolume: 760,
            bolusID: 10678,
            bolusTypeBitmask: 3,
            foodVolume: 30,
            correctionVolume: 730,
            bolusCarbs: 3,
            bolusBG: 186,
            bolusIOB: 0
        )

        let parsed: InitiateBolusRequest = MessageTester.test(
            "03d09ed03df8020000b6290000031e000000da02",
            -48,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "02d000000300ba00000000000000000000000000",
            "01d0000000007a23851bcd0708af0ac0a24f2ee7",
            "00d0fa056febc1e4710541765047"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testInitiateBolusRequest_Mobi_Extended() {
        MessageTester.initPumpState("", 1_905_413)
        let expected = InitiateBolusRequest(
            totalVolume: 250,
            bolusID: 501,
            bolusTypeBitmask: 12,
            foodVolume: 0,
            correctionVolume: 0,
            bolusCarbs: 0,
            bolusBG: 170,
            bolusIOB: 2810,
            extendedVolume: 250,
            extendedSeconds: 7200,
            extended3: 0
        )

        let parsed: InitiateBolusRequest = MessageTester.test(
            "030d9e0d3dfa000000f50100000c000000000000",
            13,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "020d00000000aa00fa0a0000fa000000201c0000",
            "010d00000000b4968b1eae36a1f4be8a1069db07",
            "000d5f7074e1705b443ff533986f"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(250, Int(parsed.extendedVolume))
        XCTAssertEqual(7200, Int(parsed.extendedSeconds))
    }
}
