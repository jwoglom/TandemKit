@testable import TandemKit
import XCTest

/// Ported from pumpX2's `DailyBasalHistoryLogTest`.
///
/// The Java test additionally asserts `getPumpTimeSecInstant()` against a UTC `Instant`; `HistoryLog`
/// has no Swift equivalent computed property (pump-time-to-`Date` conversion lives in `Dates`, which
/// applies a caller-supplied timezone offset rather than a fixed UTC one, so it is not a drop-in
/// match), so those assertions are omitted here. `pumpTimeSec` itself is still checked exactly via
/// `testSingle`'s full-field comparison, since the fixture's pump-time seconds are decoded into
/// `expected` below.
final class DailyBasalHistoryLogTests: XCTestCase {
    func testDailyBasalHistoryLog_0700() {
        // actualBatteryCharge=65, dailyTotalBasal=5.661252, iob=0.0, lastBasalRate=0.895,
        // lipoMv=3904, pumpTimeSec=445935621, sequenceNum=180238
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 445935621,
            sequenceNum: 180238,
            dailyTotalBasal: 5.661252,
            lastBasalRate: 0.895,
            iob: 0.0,
            finalEventForDay: false,
            batteryChargeRaw: 65,
            lipoMv: 3904
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "51000570941a0ec00200fa28b540b81e653f000000000041400f",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testDailyBasalHistoryLog_0800() {
        // 3601 seconds later (1 hour)
        // actualBatteryCharge=64, dailyTotalBasal=6.2405014, iob=0.0, lastBasalRate=0.218,
        // lipoMv=3901, pumpTimeSec=445939222, sequenceNum=180317
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 445939222,
            sequenceNum: 180317,
            dailyTotalBasal: 6.2405014,
            lastBasalRate: 0.218,
            iob: 0.0,
            finalEventForDay: false,
            batteryChargeRaw: 64,
            lipoMv: 3901
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "5100167e941a5dc0020030b2c740643b5f3e0000000000403d0f",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testDailyBasalHistoryLog_0900() {
        // 3599 seconds later (59m59s)
        // actualBatteryCharge=64, dailyTotalBasal=7.063834, iob=0.0, lastBasalRate=1.25,
        // lipoMv=3898, pumpTimeSec=445942821, sequenceNum=180397
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 445942821,
            sequenceNum: 180397,
            dailyTotalBasal: 7.063834,
            lastBasalRate: 1.25,
            iob: 0.0,
            finalEventForDay: false,
            batteryChargeRaw: 64,
            lipoMv: 3898
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "5100258c941aadc00200ee0ae2400000a03f0000000000403a0f",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testDailyBasalHistoryLog_1000() {
        // 3600 seconds later (1h)
        // actualBatteryCharge=64, dailyTotalBasal=7.5640016, iob=0.0, lastBasalRate=0.366,
        // lipoMv=3895, pumpTimeSec=445946421, sequenceNum=180477
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 445946421,
            sequenceNum: 180477,
            dailyTotalBasal: 7.5640016,
            lastBasalRate: 0.366,
            iob: 0.0,
            finalEventForDay: false,
            batteryChargeRaw: 64,
            lipoMv: 3895
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "5100359a941afdc002004d0cf2405a64bb3e000000000040370f",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testDailyBasalHistoryLog_1031() {
        // 1899 seconds later (31m39s)
        // actualBatteryCharge=63, dailyTotalBasal=8.036001, iob=0.0, lastBasalRate=1.25,
        // lipoMv=3888, pumpTimeSec=445948320, sequenceNum=180539
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 445948320,
            sequenceNum: 180539,
            dailyTotalBasal: 8.036001,
            lastBasalRate: 1.25,
            iob: 0.0,
            finalEventForDay: false,
            batteryChargeRaw: 63,
            lipoMv: 3888
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "5100a0a1941a3bc10200769300410000a03f00000000003f300f",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testDailyBasalHistoryLog_1056() {
        // 1461 seconds later (24m21s)
        // actualBatteryCharge=63, dailyTotalBasal=8.577333, iob=8.102918E-4, lastBasalRate=1.25,
        // lipoMv=3889, pumpTimeSec=445949781, sequenceNum=180574
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 445949781,
            sequenceNum: 180574,
            dailyTotalBasal: 8.577333,
            lastBasalRate: 1.25,
            iob: 8.102918e-4,
            finalEventForDay: false,
            batteryChargeRaw: 63,
            lipoMv: 3889
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "510055a7941a5ec10200c23c09410000a03fc369543a003f310f",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testDailyBasalHistoryLog_2340() {
        // actualBatteryCharge=55, dailyTotalBasal=15.212776, iob=3.2821338, lastBasalRate=0.14,
        // lipoMv=3833, pumpTimeSec=445995621, sequenceNum=181834
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 445995621,
            sequenceNum: 181834,
            dailyTotalBasal: 15.212776,
            lastBasalRate: 0.14,
            iob: 3.2821338,
            finalEventForDay: false,
            batteryChargeRaw: 55,
            lipoMv: 3833
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "5100655a951a4ac6020088677341295c0f3e7b0e52400037f90e",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testDailyBasalHistoryLog_2350() {
        // 601 seconds later (10m1s)
        // actualBatteryCharge=55, dailyTotalBasal=15.260943, iob=2.9004815, lastBasalRate=0.8,
        // lipoMv=3833, pumpTimeSec=445996222, sequenceNum=181849
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 445996222,
            sequenceNum: 181849,
            dailyTotalBasal: 15.260943,
            lastBasalRate: 0.8,
            iob: 2.9004815,
            finalEventForDay: false,
            batteryChargeRaw: 55,
            lipoMv: 3833
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "5100be5c951a59c60200d32c7441cdcc4c3f7da139400037f90e",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testDailyBasalHistoryLog_2358() {
        // 480 seconds later (8m)
        // actualBatteryCharge=55, dailyTotalBasal=15.394278, iob=2.7399874, lastBasalRate=0.8,
        // lipoMv=3837, pumpTimeSec=445996702, sequenceNum=181859
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 445996702,
            sequenceNum: 181859,
            dailyTotalBasal: 15.394278,
            lastBasalRate: 0.8,
            iob: 2.7399874,
            finalEventForDay: true,
            batteryChargeRaw: 55,
            lipoMv: 3837
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "51009e5e951a63c60200f64e7641cdcc4c3ff45b2f400137fd0e",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testDailyBasalHistoryLog_0000() {
        // 119 seconds later (1m59s)
        // actualBatteryCharge=55, dailyTotalBasal=0.0, iob=2.5898643, lastBasalRate=0.8,
        // lipoMv=3837, pumpTimeSec=445996821, sequenceNum=181863
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 445996821,
            sequenceNum: 181863,
            dailyTotalBasal: 0.0,
            lastBasalRate: 0.8,
            iob: 2.5898643,
            finalEventForDay: false,
            batteryChargeRaw: 55,
            lipoMv: 3837
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "5100155f951a67c6020000000000cdcc4c3f56c025400037fd0e",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testDailyBasalHistoryLog_0010() {
        // 601 seconds later (10m1s)
        // actualBatteryCharge=55, dailyTotalBasal=0.13333334, iob=2.2888513, lastBasalRate=0.8,
        // lipoMv=3837, pumpTimeSec=445997422, sequenceNum=181877
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 445997422,
            sequenceNum: 181877,
            dailyTotalBasal: 0.13333334,
            lastBasalRate: 0.8,
            iob: 2.2888513,
            finalEventForDay: false,
            batteryChargeRaw: 55,
            lipoMv: 3837
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "51006e61951a75c602008988083ecdcc4c3f8a7c12400037fd0e",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testDailyBasalHistoryLog_0016() {
        // 363 seconds later (6m3s)
        // actualBatteryCharge=55, dailyTotalBasal=0.2, iob=2.1372654, lastBasalRate=0.8,
        // lipoMv=3832, pumpTimeSec=445997785, sequenceNum=181907
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 445997785,
            sequenceNum: 181907,
            dailyTotalBasal: 0.2,
            lastBasalRate: 0.8,
            iob: 2.1372654,
            finalEventForDay: false,
            batteryChargeRaw: 55,
            lipoMv: 3832
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "5100d962951a93c60200cdcc4c3ecdcc4c3ff5c808400037f80e",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testBatteryChargeIsUnscaledPercent() {
        // byte 23 is the pump's state-of-charge, 0-100, with no scaling applied
        let parsed = HistoryLogMessageTester.testSingle(
            "51000570941a0ec00200fa28b540b81e653f000000000041400f",
            DailyBasalHistoryLog(
                pumpTimeSec: 445935621,
                sequenceNum: 180238,
                dailyTotalBasal: 5.661252,
                lastBasalRate: 0.895,
                iob: 0.0,
                finalEventForDay: false,
                batteryChargeRaw: 65,
                lipoMv: 3904
            )
        )
        XCTAssertEqual(65, parsed.batteryChargeRaw)
        XCTAssertEqual(65.0, Double(parsed.batteryChargeRaw), accuracy: 0.0)
    }

    func testLowBatteryChargeIsReportedAsLow() {
        // a 20% battery must be reported as 20%, not as the 53.9% the previous scaling emitted
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 445935621,
            sequenceNum: 180238,
            dailyTotalBasal: 5.661252,
            lastBasalRate: 0.895,
            iob: 0.0,
            finalEventForDay: false,
            batteryChargeRaw: 20,
            lipoMv: 3714
        )
        let parsed = HistoryLogMessageTester.testSingle(
            expected.cargo.hexadecimalString,
            expected
        )
        XCTAssertEqual(20, parsed.batteryChargeRaw)
        XCTAssertEqual(20.0, Double(parsed.batteryChargeRaw), accuracy: 0.0)
        XCTAssertEqual(3714, parsed.lipoMv)
    }

    func testBatteryChargeAbove127IsReadUnsigned() {
        // guards against a signed read of byte 23; outside the pump's real 0-100 range but a
        // signed read would return -1 rather than 255
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 445935621,
            sequenceNum: 180238,
            dailyTotalBasal: 5.661252,
            lastBasalRate: 0.895,
            iob: 0.0,
            finalEventForDay: false,
            batteryChargeRaw: 255,
            lipoMv: 3904
        )
        let parsed = HistoryLogMessageTester.testSingle(
            expected.cargo.hexadecimalString,
            expected
        )
        XCTAssertEqual(255, parsed.batteryChargeRaw)
    }
}
