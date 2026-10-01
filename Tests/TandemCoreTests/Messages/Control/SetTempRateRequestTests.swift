@testable import TandemKit
import XCTest

final class SetTempRateRequestTests: XCTestCase {
    func testSetTempRateRequest_0pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(minutes: 15, percent: 0)
        MessageTester.assertHexEquals(Data([0xA0, 0xBB, 0x0D, 0x00, 0x00, 0x00]), expected.cargo)

        let parsed: SetTempRateRequest = MessageTester.test(
            "0151a4511ea0bb0d0000005f6ef01fd2ed2a3276",
            81,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "005179ee6512fde74533e1f1b7d863347d27bf"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.percent)
        XCTAssertEqual(15, parsed.minutes)
    }

    func testSetTempRateRequest_1pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(minutes: 15, percent: 1)
        MessageTester.assertHexEquals(Data([0xA0, 0xBB, 0x0D, 0x00, 0x01, 0x00]), expected.cargo)

        let parsed: SetTempRateRequest = MessageTester.test(
            "017da47d1ea0bb0d000100936ef01fa736f5a248",
            125,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "007d1af9111b009e52e04b30d22241635de6bf"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.percent)
        XCTAssertEqual(15, parsed.minutes)
    }

    func testSetTempRateRequest_2pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(minutes: 15, percent: 2)
        MessageTester.assertHexEquals(Data([0xA0, 0xBB, 0x0D, 0x00, 0x02, 0x00]), expected.cargo)

        let parsed: SetTempRateRequest = MessageTester.test(
            "0190a4901ea0bb0d000200ab6ef01f8add3e9729",
            -112,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0090fde703c39a6278e3f2fd2a061b9c8dd8ee"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(2, parsed.percent)
        XCTAssertEqual(15, parsed.minutes)
    }

    func testSetTempRateRequest_10pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(minutes: 15, percent: 10)
        MessageTester.assertHexEquals(Data([0xA0, 0xBB, 0x0D, 0x00, 0x0A, 0x00]), expected.cargo)

        let parsed: SetTempRateRequest = MessageTester.test(
            "01a2a4a21ea0bb0d000a00bc6ef01f0c373adbe4",
            -94,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00a273ec2f89dc1ce285547b87c0bb95138a64"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(10, parsed.percent)
        XCTAssertEqual(15, parsed.minutes)
    }

    func testSetTempRateRequest_40pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(minutes: 15, percent: 40)
        MessageTester.assertHexEquals(Data([0xA0, 0xBB, 0x0D, 0x00, 0x28, 0x00]), expected.cargo)

        let parsed: SetTempRateRequest = MessageTester.test(
            "01b5a4b51ea0bb0d002800d46ef01fc26d64aeb1",
            -75,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00b5c5a1530bf58d12e57e4f1bf1699c8f3adf"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(40, parsed.percent)
        XCTAssertEqual(15, parsed.minutes)
    }

    func testSetTempRateRequest_50pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(minutes: 15, percent: 50)
        MessageTester.assertHexEquals(Data([0xA0, 0xBB, 0x0D, 0x00, 0x32, 0x00]), expected.cargo)

        let parsed: SetTempRateRequest = MessageTester.test(
            "01c8a4c81ea0bb0d003200e66ef01fcea48f2fac",
            -56,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00c826336f9f6a8f34304818abf9e13ca37408"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(50, parsed.percent)
        XCTAssertEqual(15, parsed.minutes)
    }

    func testSetTempRateRequest_51pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(minutes: 15, percent: 51)
        MessageTester.assertHexEquals(Data([0xA0, 0xBB, 0x0D, 0x00, 0x33, 0x00]), expected.cargo)

        let parsed: SetTempRateRequest = MessageTester.test(
            "01d8a4d81ea0bb0d003300fd6ef01f1ad8f7953c",
            -40,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00d852535070f4e7bfeb0b02bb64144c15b6f4"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(51, parsed.percent)
        XCTAssertEqual(15, parsed.minutes)
    }

    func testSetTempRateRequest_52pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(minutes: 15, percent: 52)
        MessageTester.assertHexEquals(Data([0xA0, 0xBB, 0x0D, 0x00, 0x34, 0x00]), expected.cargo)

        let parsed: SetTempRateRequest = MessageTester.test(
            "01e7a4e71ea0bb0d0034000a6ff01f3d7fba8667",
            -25,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00e7cc160c89eb7201e359591d165fcdf8bebe"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(52, parsed.percent)
        XCTAssertEqual(15, parsed.minutes)
    }

    func testSetTempRateRequest_98pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(minutes: 15, percent: 98)
        MessageTester.assertHexEquals(Data([0xA0, 0xBB, 0x0D, 0x00, 0x62, 0x00]), expected.cargo)

        let parsed: SetTempRateRequest = MessageTester.test(
            "01fba4fb1ea0bb0d0062001f6ff01f7d67b16536",
            -5,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00fbea93dfed8f17eb822192e68b924fd723df"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(98, parsed.percent)
        XCTAssertEqual(15, parsed.minutes)
    }

    func testSetTempRateRequest_140pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(minutes: 15, percent: 140)
        MessageTester.assertHexEquals(Data([0xA0, 0xBB, 0x0D, 0x00, 0x8C, 0x00]), expected.cargo)

        let parsed: SetTempRateRequest = MessageTester.test(
            "010da40d1ea0bb0d008c00316ff01f5a4be23492",
            13,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "000dfab7fdac6cfc377fcbe1d3aa7d6bc6bb05"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(140, parsed.percent)
        XCTAssertEqual(15, parsed.minutes)
    }

    func testSetTempRateRequest_180pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(minutes: 15, percent: 180)
        MessageTester.assertHexEquals(Data([0xA0, 0xBB, 0x0D, 0x00, 0xB4, 0x00]), expected.cargo)

        let parsed: SetTempRateRequest = MessageTester.test(
            "011da41d1ea0bb0d00b400406ff01f9d6f9efde6",
            29,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "001d9f6a71538a5b2a3add07b39a91fa759fba"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(180, parsed.percent)
        XCTAssertEqual(15, parsed.minutes)
    }

    func testSetTempRateRequest_199pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(minutes: 15, percent: 199)
        MessageTester.assertHexEquals(Data([0xA0, 0xBB, 0x0D, 0x00, 0xC7, 0x00]), expected.cargo)

        let parsed: SetTempRateRequest = MessageTester.test(
            "0131a4311ea0bb0d00c700526ff01febde639dbf",
            49,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "003157339f103c7394932d70ed467524abc61d"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(199, parsed.percent)
        XCTAssertEqual(15, parsed.minutes)
    }

    func testSetTempRateRequest_201pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(minutes: 15, percent: 201)
        MessageTester.assertHexEquals(Data([0xA0, 0xBB, 0x0D, 0x00, 0xC9, 0x00]), expected.cargo)

        let parsed: SetTempRateRequest = MessageTester.test(
            "0143a4431ea0bb0d00c900676ff01f7ebca592bc",
            67,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0043916ac521eded9e84d122e7b75e7a054586"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(201, parsed.percent)
        XCTAssertEqual(15, parsed.minutes)
    }

    func testSetTempRateRequest_245pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(minutes: 15, percent: 245)
        MessageTester.assertHexEquals(Data([0xA0, 0xBB, 0x0D, 0x00, 0xF5, 0x00]), expected.cargo)

        let parsed: SetTempRateRequest = MessageTester.test(
            "0155a4551ea0bb0d00f5007c6ff01f24b05dac9b",
            85,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0055e618d35684b87d8cce8c356302839098ae"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(245, parsed.percent)
        XCTAssertEqual(15, parsed.minutes)
    }

    func testSetTempRateRequest_250pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(minutes: 15, percent: 250)
        MessageTester.assertHexEquals(Data([0xA0, 0xBB, 0x0D, 0x00, 0xFA, 0x00]), expected.cargo)

        let parsed: SetTempRateRequest = MessageTester.test(
            "0167a4671ea0bb0d00fa00896ff01fc697a2ed82",
            103,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00674d86c93d7fcc55a1a57c9a6e6b7c734b6c"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(250, parsed.percent)
        XCTAssertEqual(15, parsed.minutes)
    }

    func testSetTempRateRequest_0pct_16min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(cargo: Data([0x00, 0xA6, 0x0E, 0x00, 0x00, 0x00]))

        let parsed: SetTempRateRequest = MessageTester.test(
            "017aa47a1e00a60e0000009c6ff01fd518027a01",
            122,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "007a9e3f8b12952dd41b013580028bd358981a"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.percent)
        XCTAssertEqual(16, parsed.minutes)
    }

    func testSetTempRateRequest_0pct_17min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(cargo: Data([0x60, 0x90, 0x0F, 0x00, 0x00, 0x00]))

        let parsed: SetTempRateRequest = MessageTester.test(
            "018aa48a1e60900f000000ae6ff01fe6475f9d9b",
            -118,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "008a1c9e1920361d6075162964e5bee8b87eac"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.percent)
        XCTAssertEqual(17, parsed.minutes)
    }

    func testSetTempRateRequest_0pct_18min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(cargo: Data([0xC0, 0x7A, 0x10, 0x00, 0x00, 0x00]))

        let parsed: SetTempRateRequest = MessageTester.test(
            "019ca49c1ec07a10000000c46ff01faa229302d8",
            -100,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "009cc3413fc22ebcaaa8b6919ca85c526bddca"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.percent)
        XCTAssertEqual(18, parsed.minutes)
    }

    func testSetTempRateRequest_95pct_59min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(cargo: Data([0x20, 0x04, 0x36, 0x00, 0x5F, 0x00]))

        let parsed: SetTempRateRequest = MessageTester.test(
            "01afa4af1e200436005f00df6ff01f128b115990",
            -81,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00afd1c77c1e849f7852275c0a1bc29c8d1956"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(95, parsed.percent)
        XCTAssertEqual(59, parsed.minutes)
    }

    func testSetTempRateRequest_95pct_2h15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(cargo: Data([0xA0, 0x98, 0x7B, 0x00, 0x5F, 0x00]))

        let parsed: SetTempRateRequest = MessageTester.test(
            "01bea4be1ea0987b005f00ec6ff01fdda86077e2",
            -66,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00be42130e21edebfb4193239c2a4f18b9de14"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(95, parsed.percent)
        XCTAssertEqual(2 * 60 + 15, parsed.minutes)
    }

    func testSetTempRateRequest_95pct_3h15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(cargo: Data([0x20, 0x87, 0xB2, 0x00, 0x5F, 0x00]))

        let parsed: SetTempRateRequest = MessageTester.test(
            "01d0a4d01e2087b2005f00fa6ff01fc5457a0f5f",
            -48,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00d02c5dff03f795611fa4d724e0c2e2f081ee"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(95, parsed.percent)
        XCTAssertEqual(3 * 60 + 15, parsed.minutes)
    }

    func testSetTempRateRequest_95pct_12h15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(cargo: Data([0xA0, 0xE9, 0xA0, 0x02, 0x5F, 0x00]))

        let parsed: SetTempRateRequest = MessageTester.test(
            "01e1a4e11ea0e9a0025f000e70f01fe0c7050329",
            -31,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00e1c2b68ba9ab21c5b2890fbdff983c65faa6"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(95, parsed.percent)
        XCTAssertEqual(12 * 60 + 15, parsed.minutes)
    }

    func testSetTempRateRequest_95pct_71h15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(cargo: Data([0x20, 0xE1, 0x49, 0x0F, 0x5F, 0x00]))

        let parsed: SetTempRateRequest = MessageTester.test(
            "01f3a4f31e20e1490f5f002470f01f8da7ffa546",
            -13,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00f33a8a503793fd1edeef7c7c63715a2e93d3"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(95, parsed.percent)
        XCTAssertEqual(71 * 60 + 15, parsed.minutes)
    }

    func testSetTempRateRequest_95pct_71h15min_2() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(cargo: Data([0x20, 0xE1, 0x49, 0x0F, 0x5F, 0x00]))

        let parsed: SetTempRateRequest = MessageTester.test(
            "0103a4031e20e1490f5f003670f01f44d97042ee",
            3,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "000306c26ba1833dd91cf172f3c2cb1d062486"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(95, parsed.percent)
        XCTAssertEqual(71 * 60 + 15, parsed.minutes)
    }

    func testSetTempRateRequest_95pct_72h() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(cargo: Data([0x00, 0x14, 0x73, 0x0F, 0x5F, 0x00]))

        let parsed: SetTempRateRequest = MessageTester.test(
            "0118a4181e0014730f5f004a70f01f79ae754dab",
            24,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00180002ed28543998f800552cd97030d29966"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(95, parsed.percent)
        XCTAssertEqual(72 * 60, parsed.minutes)
    }

    func testSetTempRateRequest_95pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_906_112)
        let expected = SetTempRateRequest(minutes: 15, percent: 95)
        MessageTester.assertHexEquals(Data([0xA0, 0xBB, 0x0D, 0x00, 0x5F, 0x00]), expected.cargo)

        let parsed: SetTempRateRequest = MessageTester.test(
            "0122a4221ea0bb0d005f001c998b1e37eacb5339",
            34,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00227c57675fc47f8c9bf5dec1f0d31d42a4b7"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testSetTempRateRequest_101pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateRequest(cargo: Data([0xA0, 0xBB, 0x0D, 0x00, 0x65, 0x00]))

        let parsed: SetTempRateRequest = MessageTester.test(
            "0148a4481ea0bb0d00650016eaee1fc5720c4461",
            72,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0048b8e23a6c4fb71331d0cbf3547996eb6cb5"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
