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
        XCTAssertEqual(65.0, parsed.batteryChargePercent, accuracy: 0.0)
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
        XCTAssertEqual(20.0, parsed.batteryChargePercent, accuracy: 0.0)
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

    // MARK: - Mobi fixtures
    //
    // Observed on a Tandem Mobi driven by Trio (Control-IQ off, no CGM paired), Sept 2026 BLE capture.
    // These records carry header high nibble 1. Float fields are built from the exact bit pattern
    // read out of the payload so the round trip is byte-exact.

    func testMobiFinalEventForDay_2358_05() {
        // 23:58:05 pump-local. finalEventForDay is set, yet another record 43 s later on the same
        // evening (below) carries it too, before a single NewDay at 00:00:00: the flag marks every
        // Daily Basal written in the last minutes before rollover, not one closing record.
        // dailyTotalBasal=0x411c0e5b (~9.7535), lastBasalRate=2.5, iob=0x40fa6e81 (~7.826),
        // batteryChargeRaw=92, lipoMv=4104, pumpTimeSec=589593485, sequenceNum=644069
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 589_593_485,
            sequenceNum: 644_069,
            dailyTotalBasal: Float(bitPattern: 0x411C_0E5B),
            lastBasalRate: 2.5,
            iob: Float(bitPattern: 0x40FA_6E81),
            finalEventForDay: true,
            batteryChargeRaw: 92,
            lipoMv: 4104
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "51108d7b2423e5d309005b0e1c4100002040816efa40015c0810",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertTrue(parsed.finalEventForDay)
        XCTAssertEqual(92, parsed.batteryChargeRaw)
        XCTAssertEqual(92.0, parsed.batteryChargePercent, accuracy: 0.0)
        XCTAssertEqual(4104, parsed.lipoMv)
    }

    func testMobiFinalEventForDay_2358_48() {
        // 43 seconds later, same evening as the record above; finalEventForDay is still set.
        // dailyTotalBasal=0x411c0e5b (~9.7535, unchanged), lastBasalRate=2.5,
        // iob=0x40f8a6ef (~7.770), batteryChargeRaw=92, lipoMv=4104,
        // pumpTimeSec=589593528, sequenceNum=644076
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 589_593_528,
            sequenceNum: 644_076,
            dailyTotalBasal: Float(bitPattern: 0x411C_0E5B),
            lastBasalRate: 2.5,
            iob: Float(bitPattern: 0x40F8_A6EF),
            finalEventForDay: true,
            batteryChargeRaw: 92,
            lipoMv: 4104
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "5110b87b2423ecd309005b0e1c4100002040efa6f840015c0810",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertTrue(parsed.finalEventForDay)
        XCTAssertEqual(92, parsed.batteryChargeRaw)
        XCTAssertEqual(92.0, parsed.batteryChargePercent, accuracy: 0.0)
        XCTAssertEqual(4104, parsed.lipoMv)
    }

    func testMobiMidDayRecord_0527() {
        // 05:27:29 pump-local, a regular mid-day record with finalEventForDay clear. The battery
        // byte sat 2-4 points below the live CurrentBatteryV2Response value across the capture.
        // dailyTotalBasal=0x40224b16 (~2.5358), lastBasalRate=0x3f0ccccd (0.55),
        // iob=0x3fb21f75 (~1.3916), batteryChargeRaw=88, lipoMv=4061,
        // pumpTimeSec=589526849, sequenceNum=640759
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 589_526_849,
            sequenceNum: 640_759,
            dailyTotalBasal: Float(bitPattern: 0x4022_4B16),
            lastBasalRate: Float(bitPattern: 0x3F0C_CCCD),
            iob: Float(bitPattern: 0x3FB2_1F75),
            finalEventForDay: false,
            batteryChargeRaw: 88,
            lipoMv: 4061
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "511041772323f7c60900164b2240cdcc0c3f751fb23f0058dd0f",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertFalse(parsed.finalEventForDay)
        XCTAssertEqual(88, parsed.batteryChargeRaw)
        XCTAssertEqual(88.0, parsed.batteryChargePercent, accuracy: 0.0)
        XCTAssertEqual(4061, parsed.lipoMv)
    }

    func testMobiFinalEventForDayBeforeDateChange() {
        // 18:20:34 pump-local; the next record is a DateChange written in the same second.
        let expected = DailyBasalHistoryLog(
            pumpTimeSec: 585_166_834,
            sequenceNum: 630_725,
            dailyTotalBasal: Float(bitPattern: 0x4121_FC96),
            lastBasalRate: 0.0,
            iob: Float(bitPattern: 0x3F2D_08EA),
            finalEventForDay: true,
            batteryChargeRaw: 51,
            lipoMv: 3819
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "5110f2efe022c59f090096fc214100000000ea082d3f0133eb0e",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertTrue(parsed.finalEventForDay)
        XCTAssertEqual(51.0, parsed.batteryChargePercent, accuracy: 0.0)
        XCTAssertEqual(3819, parsed.lipoMv)
    }
}
