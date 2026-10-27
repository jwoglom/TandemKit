@testable import TandemKit
import XCTest

final class SetSleepScheduleRequestTests: XCTestCase {
    private typealias SleepSchedule = ControlIQSleepScheduleResponse.SleepSchedule

    private let everyDay = MultiDay.allDays
    private let weekdays: Set<MultiDay> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    private let satSun: Set<MultiDay> = [.saturday, .sunday]
    private let noDays: Set<MultiDay> = []

    private func schedule(_ enabled: Int, _ days: Set<MultiDay>, _ start: MinsTime, _ end: MinsTime) -> SleepSchedule {
        SleepSchedule(enabled: enabled, activeDays: MultiDay.toBitmask(Array(days)), startTime: start.encode, endTime: end.encode)
    }

    func testSetSleepScheduleRequest_set0_rawBytes() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_905_836)
        let expected = SetSleepScheduleRequest(cargo: Data([0x00, 0x01, 0x7F, 0x00, 0x00, 0x9F, 0x05, 0x03]))

        let parsed: SetSleepScheduleRequest = MessageTester.test(
            "02a2cea22000017f00009f0503ff978b1e828836",
            -94,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01a222d3b77a25443cc291be989dc841df1a8a75",
            "00a266"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.slot)
        XCTAssertEqual(1, parsed.schedule.enabled)
        XCTAssertEqual(MultiDay.allDays, MultiDay.fromBitmask(parsed.schedule.activeDays))
        XCTAssertEqual(MinsTime(0), MinsTime(parsed.schedule.startTime))
        XCTAssertEqual(MinsTime(hour: 23, min: 59), MinsTime(parsed.schedule.endTime))
        XCTAssertEqual(parsed.changedFields, [.base, .enabled])
    }

    func testSetSleepScheduleRequest_disable0() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_905_836)
        let expected = SetSleepScheduleRequest(cargo: Data([0x00, 0x00, 0x7F, 0x00, 0x00, 0x9F, 0x05, 0x03]))

        let parsed: SetSleepScheduleRequest = MessageTester.test(
            "02abceab2000007f00009f050311988b1ef9651b",
            -85,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01abc15275490acd94a3416d8cfc038cd7ff461a",
            "00ab0c"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.slot)
        XCTAssertEqual(0, parsed.schedule.enabled)
        XCTAssertEqual(MultiDay.allDays, MultiDay.fromBitmask(parsed.schedule.activeDays))
        XCTAssertEqual(MinsTime(0), MinsTime(parsed.schedule.startTime))
        XCTAssertEqual(MinsTime(hour: 23, min: 59), MinsTime(parsed.schedule.endTime))
        XCTAssertEqual(parsed.changedFields, [.base, .enabled])
    }

    func testSetSleepScheduleRequest_constructorSetsFields() {
        let request = SetSleepScheduleRequest(
            slot: 1,
            schedule: SleepSchedule(enabled: 1, activeDays: 31, startTime: 60, endTime: 600),
            changedFields: SleepScheduleFields(rawValue: 5)
        )

        MessageTester.assertHexEquals(Data([0x01, 0x01, 0x1F, 0x3C, 0x00, 0x58, 0x02, 0x05]), request.cargo)
        XCTAssertEqual(request.slot, 1)
        XCTAssertEqual(request.changedFields.rawValue, 5)
        XCTAssertEqual(request.changedFields, [.base, .activeDays])
        XCTAssertEqual(MultiDay.fromBitmask(request.schedule.activeDays), weekdays)
        XCTAssertEqual(MinsTime(request.schedule.startTime), MinsTime(hour: 1, min: 0))
        XCTAssertEqual(MinsTime(request.schedule.endTime), MinsTime(hour: 10, min: 0))
    }

    func testBuiltRequestAlwaysCarriesBase() {
        let request = SetSleepScheduleRequest(
            slot: 1,
            schedule: SleepSchedule(enabled: 1, activeDays: 31, startTime: 60, endTime: 600),
            changedFields: .activeDays
        )

        XCTAssertEqual(request.changedFields, [.base, .activeDays])
    }

    func testUnchangedScheduleFlagsOnlyBase() {
        let unchanged = schedule(1, everyDay, MinsTime(hour: 23, min: 0), MinsTime(hour: 7, min: 0))

        XCTAssertEqual(SleepScheduleFields.between(unchanged, unchanged), [])
        XCTAssertEqual(SetSleepScheduleRequest(slot: 0, previous: unchanged, updated: unchanged).changedFields, .base)
    }

    // Every SetSleepScheduleRequest the Mobi app (iOS) sent while editing sleep schedules on
    // 2026-10-27, in order, from pumpX2. "before" is the pump's slot as read just before; each was
    // answered with status 0 and read back as "after". Slot 0 is the app's Sleep Schedule 1.

    func testSetSleepScheduleRequest_mobi01_ss1EndTime() throws {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 430)

        // Sleep Schedule 1: changed End Time from 11:59 PM to 10:00 AM.
        let before = schedule(1, everyDay, MinsTime(hour: 0, min: 0), MinsTime(hour: 23, min: 59))
        let after = schedule(1, everyDay, MinsTime(hour: 0, min: 0), MinsTime(hour: 10, min: 0))
        let expected = SetSleepScheduleRequest(slot: 0, previous: before, updated: after)

        let parsed: SetSleepScheduleRequest = MessageTester.test(
            // 2026-10-27T20:15:46.379000+00:00
            "02b5ceb52000017f0000580211f2836723fff760",
            -75,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01b55e84de41869b4ea538d52f5879ee2475a666",
            "00b50e"
        )

        MessageTester.assertHexEquals(try XCTUnwrap(Data(hexadecimalString: "00017f0000580211")), parsed.cargo)
        XCTAssertEqual(parsed.slot, 0)
        XCTAssertEqual(parsed.schedule, after)
        XCTAssertEqual(parsed.changedFields, [.base, .endTime])
    }

    func testSetSleepScheduleRequest_mobi02_ss1StartTime() throws {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 430)

        // Sleep Schedule 1: changed Start Time from 12:00 AM to 1:00 AM.
        let before = schedule(1, everyDay, MinsTime(hour: 0, min: 0), MinsTime(hour: 10, min: 0))
        let after = schedule(1, everyDay, MinsTime(hour: 1, min: 0), MinsTime(hour: 10, min: 0))
        let expected = SetSleepScheduleRequest(slot: 0, previous: before, updated: after)

        let parsed: SetSleepScheduleRequest = MessageTester.test(
            // 2026-10-27T20:15:54.129000+00:00
            "02baceba2000017f3c00580209fa836723e2e9a2",
            -70,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01ba815b878f67ac33a97deded2039513ab6a64c",
            "00ba10"
        )

        MessageTester.assertHexEquals(try XCTUnwrap(Data(hexadecimalString: "00017f3c00580209")), parsed.cargo)
        XCTAssertEqual(parsed.slot, 0)
        XCTAssertEqual(parsed.schedule, after)
        XCTAssertEqual(parsed.changedFields, [.base, .startTime])
    }

    func testSetSleepScheduleRequest_mobi03_ss1Weekdays() throws {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 430)

        // Sleep Schedule 1: unchecked Sunday and Saturday.
        let before = schedule(1, everyDay, MinsTime(hour: 1, min: 0), MinsTime(hour: 10, min: 0))
        let after = schedule(1, weekdays, MinsTime(hour: 1, min: 0), MinsTime(hour: 10, min: 0))
        let expected = SetSleepScheduleRequest(slot: 0, previous: before, updated: after)

        let parsed: SetSleepScheduleRequest = MessageTester.test(
            // 2026-10-27T20:16:00.720000+00:00
            "02c2cec22000011f3c0058020500846723ed34d8",
            -62,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01c24bc95ba9e349eb782b6c92649df7745c2793",
            "00c2c2"
        )

        MessageTester.assertHexEquals(try XCTUnwrap(Data(hexadecimalString: "00011f3c00580205")), parsed.cargo)
        XCTAssertEqual(parsed.slot, 0)
        XCTAssertEqual(parsed.schedule, after)
        XCTAssertEqual(parsed.changedFields, [.base, .activeDays])
    }

    func testSetSleepScheduleRequest_mobi04_ss1DaysStartEnd() throws {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 430)

        // Sleep Schedule 1: changed both times, unchecked Monday-Friday and checked Saturday and Sunday.
        let before = schedule(1, weekdays, MinsTime(hour: 1, min: 0), MinsTime(hour: 10, min: 0))
        let after = schedule(1, satSun, MinsTime(hour: 2, min: 0), MinsTime(hour: 9, min: 0))
        let expected = SetSleepScheduleRequest(slot: 0, previous: before, updated: after)

        let parsed: SetSleepScheduleRequest = MessageTester.test(
            // 2026-10-27T20:16:13.937000+00:00
            "02c7cec72000016078001c021d0d846723c98b05",
            -57,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01c757fadab087b57780e086f7d1e3b0b8d877b8",
            "00c754"
        )

        MessageTester.assertHexEquals(try XCTUnwrap(Data(hexadecimalString: "00016078001c021d")), parsed.cargo)
        XCTAssertEqual(parsed.slot, 0)
        XCTAssertEqual(parsed.schedule, after)
        XCTAssertEqual(parsed.changedFields, [.base, .activeDays, .startTime, .endTime])
    }

    func testSetSleepScheduleRequest_mobi05_ss1Off() throws {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 430)

        // Sleep Schedule 1: switched the schedule off. Days and times are sent unchanged.
        let before = schedule(1, satSun, MinsTime(hour: 2, min: 0), MinsTime(hour: 9, min: 0))
        let after = schedule(0, satSun, MinsTime(hour: 2, min: 0), MinsTime(hour: 9, min: 0))
        let expected = SetSleepScheduleRequest(slot: 0, previous: before, updated: after)

        let parsed: SetSleepScheduleRequest = MessageTester.test(
            // 2026-10-27T20:16:18.055000+00:00
            "02cecece2000006078001c0203128467232a4518",
            -50,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01ce9d02175972937e30eb4481835d97a4208762",
            "00cef1"
        )

        MessageTester.assertHexEquals(try XCTUnwrap(Data(hexadecimalString: "00006078001c0203")), parsed.cargo)
        XCTAssertEqual(parsed.slot, 0)
        XCTAssertEqual(parsed.schedule, after)
        XCTAssertEqual(parsed.changedFields, [.base, .enabled])
    }

    func testSetSleepScheduleRequest_mobi06_ss1OnEveryNight() throws {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 491)

        // Sleep Schedule 1: switched back on, changed both times and checked Monday-Friday.
        let before = schedule(0, satSun, MinsTime(hour: 2, min: 0), MinsTime(hour: 9, min: 0))
        let after = schedule(1, everyDay, MinsTime(hour: 23, min: 0), MinsTime(hour: 7, min: 0))
        let expected = SetSleepScheduleRequest(slot: 0, previous: before, updated: after)

        let parsed: SetSleepScheduleRequest = MessageTester.test(
            // 2026-10-27T20:16:31.914000+00:00
            "02d7ced72000017f6405a4011f1f846723f7e789",
            -41,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01d7503f2bd9ee97f5980c77c0ff851e95d988be",
            "00d799"
        )

        MessageTester.assertHexEquals(try XCTUnwrap(Data(hexadecimalString: "00017f6405a4011f")), parsed.cargo)
        XCTAssertEqual(parsed.slot, 0)
        XCTAssertEqual(parsed.schedule, after)
        XCTAssertEqual(parsed.changedFields, [.base, .enabled, .activeDays, .startTime, .endTime])
    }

    func testSetSleepScheduleRequest_mobi07_ss2On() throws {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 551)

        // Sleep Schedule 2: switched on for the first time, Sat and Sun, 9:00 AM - 10:00 AM. The app
        // refused three earlier saves for overlapping Sleep Schedule 1; "before" is an unused slot.
        let before = schedule(0, noDays, MinsTime(hour: 23, min: 0), MinsTime(hour: 7, min: 0))
        let after = schedule(1, satSun, MinsTime(hour: 9, min: 0), MinsTime(hour: 10, min: 0))
        let expected = SetSleepScheduleRequest(slot: 1, previous: before, updated: after)

        let parsed: SetSleepScheduleRequest = MessageTester.test(
            // 2026-10-27T20:17:39.046000+00:00
            "02e2cee2200101601c0258021f63846723cfb8f3",
            -30,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01e2cb0689ce18bd82e003125636d15fd1be3ae1",
            "00e25e"
        )

        MessageTester.assertHexEquals(try XCTUnwrap(Data(hexadecimalString: "0101601c0258021f")), parsed.cargo)
        XCTAssertEqual(parsed.slot, 1)
        XCTAssertEqual(parsed.schedule, after)
        XCTAssertEqual(parsed.changedFields, [.base, .enabled, .activeDays, .startTime, .endTime])
    }

    func testSetSleepScheduleRequest_mobi08_ss2AddMonday() throws {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 551)

        // Sleep Schedule 2: checked Monday.
        let before = schedule(1, satSun, MinsTime(hour: 9, min: 0), MinsTime(hour: 10, min: 0))
        let after = schedule(1, [.monday, .saturday, .sunday], MinsTime(hour: 9, min: 0), MinsTime(hour: 10, min: 0))
        let expected = SetSleepScheduleRequest(slot: 1, previous: before, updated: after)

        let parsed: SetSleepScheduleRequest = MessageTester.test(
            // 2026-10-27T20:17:43.867000+00:00
            "02e6cee6200101611c02580205678467230fc6c0",
            -26,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01e68467c2008897e598426ad718c43034640839",
            "00e6dd"
        )

        MessageTester.assertHexEquals(try XCTUnwrap(Data(hexadecimalString: "0101611c02580205")), parsed.cargo)
        XCTAssertEqual(parsed.slot, 1)
        XCTAssertEqual(parsed.schedule, after)
        XCTAssertEqual(parsed.changedFields, [.base, .activeDays])
    }

    func testSetSleepScheduleRequest_mobi09_ss2RemoveMonday() throws {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 551)

        // Sleep Schedule 2: unchecked Monday.
        let before = schedule(1, [.monday, .saturday, .sunday], MinsTime(hour: 9, min: 0), MinsTime(hour: 10, min: 0))
        let after = schedule(1, satSun, MinsTime(hour: 9, min: 0), MinsTime(hour: 10, min: 0))
        let expected = SetSleepScheduleRequest(slot: 1, previous: before, updated: after)

        let parsed: SetSleepScheduleRequest = MessageTester.test(
            // 2026-10-27T20:17:49.007000+00:00
            "02eeceee200101601c025802056c846723cb135f",
            -18,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01eead956cbeef7e1f4329c216ff1cd502cfe098",
            "00eee1"
        )

        MessageTester.assertHexEquals(try XCTUnwrap(Data(hexadecimalString: "0101601c02580205")), parsed.cargo)
        XCTAssertEqual(parsed.slot, 1)
        XCTAssertEqual(parsed.schedule, after)
        XCTAssertEqual(parsed.changedFields, [.base, .activeDays])
    }

    func testSetSleepScheduleRequest_mobi10_ss2Off() throws {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 551)

        // Sleep Schedule 2: switched the schedule off. Days and times are sent unchanged.
        let before = schedule(1, satSun, MinsTime(hour: 9, min: 0), MinsTime(hour: 10, min: 0))
        let after = schedule(0, satSun, MinsTime(hour: 9, min: 0), MinsTime(hour: 10, min: 0))
        let expected = SetSleepScheduleRequest(slot: 1, previous: before, updated: after)

        let parsed: SetSleepScheduleRequest = MessageTester.test(
            // 2026-10-27T20:17:52.431000+00:00
            "02f2cef2200100601c025802037084672312acd1",
            -14,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01f202a405d291c66d9c48d071558e3ca57779ad",
            "00f2d2"
        )

        MessageTester.assertHexEquals(try XCTUnwrap(Data(hexadecimalString: "0100601c02580203")), parsed.cargo)
        XCTAssertEqual(parsed.slot, 1)
        XCTAssertEqual(parsed.schedule, after)
        XCTAssertEqual(parsed.changedFields, [.base, .enabled])
    }

    func testSetSleepScheduleRequest_mobi11_ss1OffAgain() throws {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 551)

        // Sleep Schedule 1: switched the schedule off. Days and times are sent unchanged.
        let before = schedule(1, everyDay, MinsTime(hour: 23, min: 0), MinsTime(hour: 7, min: 0))
        let after = schedule(0, everyDay, MinsTime(hour: 23, min: 0), MinsTime(hour: 7, min: 0))
        let expected = SetSleepScheduleRequest(slot: 0, previous: before, updated: after)

        let parsed: SetSleepScheduleRequest = MessageTester.test(
            // 2026-10-27T20:17:58.070000+00:00
            "02facefa2000007f6405a4010376846723c27b25",
            -6,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01fa965219d450fb1dcc66e92d8d285df26bf9ff",
            "00fabd"
        )

        MessageTester.assertHexEquals(try XCTUnwrap(Data(hexadecimalString: "00007f6405a40103")), parsed.cargo)
        XCTAssertEqual(parsed.slot, 0)
        XCTAssertEqual(parsed.schedule, after)
        XCTAssertEqual(parsed.changedFields, [.base, .enabled])
    }
}
