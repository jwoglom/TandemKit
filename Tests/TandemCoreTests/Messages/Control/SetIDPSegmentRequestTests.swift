@testable import TandemKit
import XCTest

final class SetIDPSegmentRequestTests: XCTestCase {
    func testSetIDPSegmentRequest_idp1_segment0_midnight() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 1,
            segmentIndex: 0,
            operation: .modifySegmentId,
            profileStartTime: 0,
            profileBasalRate: 2000,
            profileCarbRatio: 3000,
            profileTargetBG: 100,
            profileISF: 2,
            idpStatusId: bitmask(.BASAL_RATE)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "022daa2d29010100000000d007b80b0000640002",
            45,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "012d00018f493e20e5c9cdb2d482ccc51cb25c03",
            "002dbc127447c7c401957f01"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testSetIDPSegmentRequest_idp1_segment1new_1am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 1,
            segmentIndex: 0,
            operation: .createSegment,
            profileStartTime: 60,
            profileBasalRate: 1000,
            profileCarbRatio: 3000,
            profileTargetBG: 100,
            profileISF: 2,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .CORRECTION_FACTOR, .TARGET_BG, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "02e1aae129010100013c00e803b80b0000640002",
            -31,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01e1001ff9483e203d291074f2f3bf6ac7a0cd81",
            "00e12ea287e849d9a355b90b"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testSetIDPSegmentRequest_idp1_segment1_DELETE() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 1,
            segmentIndex: 1,
            operation: .deleteSegmentId,
            profileStartTime: 60,
            profileBasalRate: 1000,
            profileCarbRatio: 3000,
            profileTargetBG: 100,
            profileISF: 2,
            idpStatusId: 31
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "02ebaaeb29010101023c00e803b80b0000640002",
            -21,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01eb001f0d493e20f3d3fd4546228ab2f88b6a5c",
            "00ebf1e0a4b8bfe566ed1e18"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario01_NewIdpSegment8am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 0,
            segmentIndex: 0,
            operation: .createSegment,
            profileStartTime: 480,
            profileBasalRate: 800,
            profileCarbRatio: 20000,
            profileTargetBG: 100,
            profileISF: 10,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .CORRECTION_FACTOR, .TARGET_BG, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "02beaabe2901000001e0012003204e000064000a",
            -66,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01be001f4f2c47203ab6442634108746c361cf93",
            "00be6a4346676362e432e2f4"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario02_NewIdpSegment9pm() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 0,
            segmentIndex: 0,
            operation: .createSegment,
            profileStartTime: 12 * 60 + 9 * 60,
            profileBasalRate: 900,
            profileCarbRatio: 20000,
            profileTargetBG: 100,
            profileISF: 10,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .CORRECTION_FACTOR, .TARGET_BG, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "02ccaacc2901000001ec048403204e000064000a",
            -52,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01cc001f6b2c4720123382409ff68413ef1f778a",
            "00ccba1823b05b1a2fb748f0"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario03_Change9pmTo9am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 0,
            segmentIndex: 2,
            operation: .modifySegmentId,
            profileStartTime: 540,
            profileBasalRate: 900,
            profileCarbRatio: 20000,
            profileTargetBG: 100,
            profileISF: 10,
            idpStatusId: bitmask(.START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "02d3aad329010002001c028403204e000064000a",
            -45,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01d30010882c4720170d4703a73a2a611b117cf4",
            "00d3c6271cb71a36f667772e"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario04_New10am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 0,
            segmentIndex: 0,
            operation: .createSegment,
            profileStartTime: 600,
            profileBasalRate: 1000,
            profileCarbRatio: 20000,
            profileTargetBG: 100,
            profileISF: 10,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .CORRECTION_FACTOR, .TARGET_BG, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "02e5aae529010000015802e803204e000064000a",
            -27,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01e5001fab2c47206889b14804479e1ad72797d4",
            "00e510ebcdf9ad9a27cd030c"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario05_New5pm() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 0,
            segmentIndex: 0,
            operation: .createSegment,
            profileStartTime: 1380,
            profileBasalRate: 1100,
            profileCarbRatio: 20000,
            profileTargetBG: 100,
            profileISF: 10,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .CORRECTION_FACTOR, .TARGET_BG, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "02f7aaf7290100000164054c04204e000064000a",
            -9,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01f7001fcb2c4720a80890da27608f1e5c0cb486",
            "00f74ab88a5a2659c670bbb2"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario06_DeleteSegment10am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 0,
            segmentIndex: 3,
            operation: .deleteSegmentId,
            profileStartTime: 600,
            profileBasalRate: 1000,
            profileCarbRatio: 20000,
            profileTargetBG: 100,
            profileISF: 10,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .CORRECTION_FACTOR, .TARGET_BG, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "0205aa0529010003025802e803204e000064000a",
            5,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0105001fe62c4720070f244c8b4c8a3b5a3928fd",
            "00052a1947f769ca78019ec5"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario07_NewSegment1am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 0,
            segmentIndex: 0,
            operation: .createSegment,
            profileStartTime: 60,
            profileBasalRate: 100,
            profileCarbRatio: 1000,
            profileTargetBG: 100,
            profileISF: 1,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .CORRECTION_FACTOR, .TARGET_BG, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "0210aa1029010000013c006400e8030000640001",
            16,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0110001f002d4720e8a8dee8607cf1a5abe649c9",
            "0010bff0bcc438643ccc6621"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario08_Change8amTo2am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 0,
            segmentIndex: 2,
            operation: .modifySegmentId,
            profileStartTime: 120,
            profileBasalRate: 200,
            profileCarbRatio: 20000,
            profileTargetBG: 100,
            profileISF: 10,
            idpStatusId: bitmask(.BASAL_RATE, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "021faa1f29010002007800c800204e000064000a",
            31,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "011f00111d2d47200a31dba06b57c2183a139f9b",
            "001f6ccc67dd2a85f0d01031"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario09_Change9amTo3am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 0,
            segmentIndex: 3,
            operation: .modifySegmentId,
            profileStartTime: 180,
            profileBasalRate: 300,
            profileCarbRatio: 20000,
            profileTargetBG: 100,
            profileISF: 10,
            idpStatusId: bitmask(.BASAL_RATE, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "0230aa302901000300b4002c01204e000064000a",
            48,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01300011382d4720ca9c5606c6c8673ea18d67e8",
            "0030952e74edd52c25721c5b"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario10_Delete1am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 0,
            segmentIndex: 1,
            operation: .deleteSegmentId,
            profileStartTime: 60,
            profileBasalRate: 100,
            profileCarbRatio: 1000,
            profileTargetBG: 100,
            profileISF: 1,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .TARGET_BG, .CORRECTION_FACTOR, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "0240aa4029010001023c006400e8030000640001",
            64,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0140001f4c2d4720d8f5c1e02bec75b272687944",
            "0040f5dd6d354ec61dcf6c4b"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario11_Delete2am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 0,
            segmentIndex: 1,
            operation: .deleteSegmentId,
            profileStartTime: 120,
            profileBasalRate: 200,
            profileCarbRatio: 20000,
            profileTargetBG: 100,
            profileISF: 10,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .TARGET_BG, .CORRECTION_FACTOR, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "024daa4d29010001027800c800204e000064000a",
            77,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "014d001f6a2d47200397f1bd2565e985aa7e8a79",
            "004d344542517418b8e83bf0"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario12_Delete11pm() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 0,
            segmentIndex: 2,
            operation: .deleteSegmentId,
            profileStartTime: 1380,
            profileBasalRate: 1100,
            profileCarbRatio: 20000,
            profileTargetBG: 100,
            profileISF: 10,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .TARGET_BG, .CORRECTION_FACTOR, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "0257aa57290100020264054c04204e000064000a",
            87,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0157001f8b2d4720272dcdaab193bdfda46fe90d",
            "005715458a5d6832e01b250b"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario13_ModifyMidnightBasal() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 0,
            segmentIndex: 0,
            operation: .modifySegmentId,
            profileStartTime: 0,
            profileBasalRate: 100,
            profileCarbRatio: 1000,
            profileTargetBG: 100,
            profileISF: 1,
            idpStatusId: bitmask(.BASAL_RATE)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "026daa6d290100000000006400e8030000640001",
            109,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "016d0001ed2d47209d4088c5ff6aa859578cb577",
            "006d33d6c3067cf35ff71917"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario14_Add2am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 0,
            segmentIndex: 0,
            operation: .createSegment,
            profileStartTime: 120,
            profileBasalRate: 200,
            profileCarbRatio: 1000,
            profileTargetBG: 100,
            profileISF: 1,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .TARGET_BG, .CORRECTION_FACTOR, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "0276aa7629010000017800c800e8030000640001",
            118,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0176001f102e47206ae87cb08dd47a4c41f4de4c",
            "0076429e0b5407e062d3217a"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario15_Delete3am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 0,
            segmentIndex: 2,
            operation: .deleteSegmentId,
            profileStartTime: 180,
            profileBasalRate: 300,
            profileCarbRatio: 20000,
            profileTargetBG: 100,
            profileISF: 10,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .TARGET_BG, .CORRECTION_FACTOR, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "0281aa812901000202b4002c01204e000064000a",
            -127,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0181001f232e47207f6ecb83dfea20ae50b9b3dc",
            "0081185ad87a949808499d99"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario16_Delete2am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 1,
            profileIndex: 0,
            segmentIndex: 1,
            operation: .deleteSegmentId,
            profileStartTime: 120,
            profileBasalRate: 200,
            profileCarbRatio: 1000,
            profileTargetBG: 100,
            profileISF: 1,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .TARGET_BG, .CORRECTION_FACTOR, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "028eaa8e29010001027800c800e8030000640001",
            -114,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "018e001f322e4720d561e184028402d443d2832a",
            "008ef5f9e512d5e3f1aaa222"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario20_ProfCIQ_ChangeMidnight0Basal() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 0,
            profileIndex: 1,
            segmentIndex: 0,
            operation: .modifySegmentId,
            profileStartTime: 0,
            profileBasalRate: 0,
            profileCarbRatio: 6000,
            profileTargetBG: 110,
            profileISF: 30,
            idpStatusId: bitmask(.BASAL_RATE)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "02d5aad5290001000000000000701700006e001e",
            -43,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01d5000188464720bb94e711b450f18986ad5a00",
            "00d51a73d679f451f005bbb5"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario21_ProfCIQ_New1am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 0,
            profileIndex: 1,
            segmentIndex: 0,
            operation: .createSegment,
            profileStartTime: 60,
            profileBasalRate: 1000,
            profileCarbRatio: 3000,
            profileTargetBG: 110,
            profileISF: 2,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .TARGET_BG, .CORRECTION_FACTOR, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "02e4aae429000100013c00e803b80b00006e0002",
            -28,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01e4001fe746472011dddb73e713298984cb0ef6",
            "00e4cf0e98f48a383e0ff345"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario22_ProfCIQ_Delete1am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 0,
            profileIndex: 1,
            segmentIndex: 1,
            operation: .deleteSegmentId,
            profileStartTime: 60,
            profileBasalRate: 1000,
            profileCarbRatio: 3000,
            profileTargetBG: 110,
            profileISF: 2,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .TARGET_BG, .CORRECTION_FACTOR, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "02f0aaf029000101023c00e803b80b00006e0002",
            -16,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01f0001f0a4747209039e5d573e0bce25dfea9b1",
            "00f0730c022161c4e63e9ca5"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario23_ProfCIQ_Delete8am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 0,
            profileIndex: 1,
            segmentIndex: 1,
            operation: .deleteSegmentId,
            profileStartTime: 480,
            profileBasalRate: 1200,
            profileCarbRatio: 6000,
            profileTargetBG: 110,
            profileISF: 30,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .TARGET_BG, .CORRECTION_FACTOR, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "0201aa012900010102e001b004701700006e001e",
            1,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0101001f3047472038bce4d7667982c1938b392a",
            "0001b68487f1b19428ac1da8"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario32_ProfC_New1am() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 2,
            profileIndex: 1,
            segmentIndex: 0,
            operation: .createSegment,
            profileStartTime: 60,
            profileBasalRate: 100,
            profileCarbRatio: 20000,
            profileTargetBG: 100,
            profileISF: 10,
            idpStatusId: bitmask(.BASAL_RATE, .CARB_RATIO, .TARGET_BG, .CORRECTION_FACTOR, .START_TIME)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "0246aa4629020100013c006400204e000064000a",
            70,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0146001f4e48472048909b74af7e295eea7f8227",
            "00461e2555dacc8c479a682f"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    func testScenario45_Set1amProfCDup() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetIDPSegmentRequest(
            idpId: 4,
            profileIndex: 1,
            segmentIndex: 1,
            operation: .modifySegmentId,
            profileStartTime: 60,
            profileBasalRate: 110,
            profileCarbRatio: 20000,
            profileTargetBG: 100,
            profileISF: 10,
            idpStatusId: bitmask(.BASAL_RATE)
        )

        let parsed: SetIDPSegmentRequest = MessageTester.test(
            "027eaa7e29040101003c006e00204e000064000a",
            126,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "017e000127494720a102f4a7574aad168a3d3c6c",
            "007e6009cc5ed6116ec63515"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSameFields(parsed, expected)
    }

    private func bitmask(_ statuses: IDPSegmentResponse.IDPSegmentStatus...) -> Int {
        statuses.reduce(0) { $0 | $1.rawValue }
    }

    private func assertSameFields(
        _ parsed: SetIDPSegmentRequest,
        _ expected: SetIDPSegmentRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(parsed.idpId, expected.idpId, "idpId", file: file, line: line)
        XCTAssertEqual(parsed.profileIndex, expected.profileIndex, "profileIndex", file: file, line: line)
        XCTAssertEqual(parsed.segmentIndex, expected.segmentIndex, "segmentIndex", file: file, line: line)
        XCTAssertEqual(parsed.operationId, expected.operationId, "operationId", file: file, line: line)
        XCTAssertEqual(parsed.profileStartTime, expected.profileStartTime, "profileStartTime", file: file, line: line)
        XCTAssertEqual(parsed.profileBasalRate, expected.profileBasalRate, "profileBasalRate", file: file, line: line)
        XCTAssertEqual(parsed.profileCarbRatio, expected.profileCarbRatio, "profileCarbRatio", file: file, line: line)
        XCTAssertEqual(parsed.profileTargetBG, expected.profileTargetBG, "profileTargetBG", file: file, line: line)
        XCTAssertEqual(parsed.profileISF, expected.profileISF, "profileISF", file: file, line: line)
        XCTAssertEqual(parsed.idpStatusId, expected.idpStatusId, "idpStatusId", file: file, line: line)
    }
}
