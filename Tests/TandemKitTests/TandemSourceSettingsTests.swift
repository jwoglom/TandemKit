@testable import TandemKit
import XCTest

final class TandemSourceSettingsTests: XCTestCase {
    private func cargo(_ size: Int, _ bytes: [Int: [UInt8]] = [:]) -> Data {
        var data = Data(count: size)
        for (offset, value) in bytes {
            data.replaceSubrange(offset ..< offset + value.count, with: value)
        }
        return data
    }

    private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
    private func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16(v >> 16) }

    private func reads(segmentStatus: UInt8 = 0x0F, hardwareInfo: Data? = nil) -> TandemSourceSettingsReads {
        let name = Array("Synthetic".utf8) + [UInt8](repeating: 0, count: 16 - "Synthetic".utf8.count)
        return TandemSourceSettingsReads(
            globals: PumpGlobalsResponse(cargo: cargo(14, [7: [7]])),
            reminders: RemindersResponse(cargo: cargo(105)),
            pumpSettings: PumpSettingsResponse(cargo: cargo(9)),
            glucoseAlerts: CGMGlucoseAlertSettingsResponse(cargo: cargo(12, [5: [0xFF]])),
            rateAlerts: CGMRateAlertSettingsResponse(cargo: cargo(6)),
            outOfRangeAlert: CGMOORAlertSettingsResponse(cargo: cargo(3)),
            cgmHardware: CGMHardwareInfoResponse(cargo: hardwareInfo ?? cargo(17)),
            profileStatus: ProfileStatusResponse(cargo: cargo(8, [0: [1], 1: [1, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF], 7: [0]])),
            profiles: [(
                settings: IDPSettingsResponse(cargo: cargo(23, [0: [1], 1: name, 17: [1], 18: le16(300), 20: le16(25000), 22: [1]])),
                segments: [IDPSegmentResponse(cargo: cargo(15, [0: [1], 1: [0], 4: le16(800), 6: le32(10000), 10: le16(110), 12: le16(50), 14: [segmentStatus]]))]
            )],
            basalLimit: BasalLimitSettingsResponse(cargo: cargo(8)),
            globalMaxBolus: GlobalMaxBolusSettingsResponse(cargo: cargo(4)),
            controlIQ: ControlIQInfoV2Response(cargo: cargo(19)),
            sleepSchedule: ControlIQSleepScheduleResponse(cargo: cargo(24)),
            localization: LocalizationResponse(cargo: cargo(7, [1: [255]]))
        )
    }

    private func json(_ settings: TandemSourceSettings) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: settings.encoded()) as! [String: Any]
    }

    private func keyPaths(_ value: Any, _ prefix: String = "") -> Set<String> {
        if let dict = value as? [String: Any] {
            return dict.reduce(into: Set<String>()) { paths, entry in
                let path = prefix.isEmpty ? entry.key : "\(prefix).\(entry.key)"
                paths.insert(path)
                paths.formUnion(keyPaths(entry.value, path))
            }
        }
        if let array = value as? [Any], let first = array.first {
            return keyPaths(first, prefix + "[]")
        }
        return []
    }

    func testKeysMatchTheIOSAppsSettingsJSON() throws {
        let paths = keyPaths(try json(TandemSourceSettings(reads())))

        let reminder = ["activeDays", "enabled", "endTimeMinutes", "frequencyMinutes", "startTimeMinutes", "status"]
        let sleep = ["ActiveDays", "Enabled", "EndTime", "StartTime"]
        var expected: Set<String> = [
            "basalLimitSettings", "basalLimitSettings.basalLimit", "basalLimitSettings.basalLimitDefault",
            "globalMaxBolusSettings", "globalMaxBolusSettings.maxBolus", "globalMaxBolusSettings.maxBolusDefault",
            "globals", "globals.quickBolusSettings", "globals.volumeSettings",
            "localizationSettings", "localizationSettings.glucoseUOM", "localizationSettings.languageSelected", "localizationSettings.regionSelected",
            "profiles", "profiles.activeIdp", "profiles.activeSegment", "profiles.numberOfProfiles", "profiles.profile",
            "pumpSettings", "reminders", "cgmSettings", "controlIQSettings",
            "reminders.highBGThreshold", "reminders.lowBGThreshold", "reminders.siteChangeDays", "reminders.status",
        ]
        expected.formUnion(["enabled", "entryType", "incrementCarbs", "incrementUnits", "status"].map { "globals.quickBolusSettings.\($0)" })
        expected.formUnion(["alarmAnnun", "alertAnnun", "bolusAnnun", "buttonAnnun", "fillTubingAnnun", "quickBolusAnnun", "reminderAnnun"].map { "globals.volumeSettings.\($0)" })
        expected.formUnion(["carbEntry", "idp", "insulinDuration", "maxBolus", "name", "tDependentNum", "tDependentSegs"].map { "profiles.profile[].\($0)" })
        expected.formUnion(["basalRate", "carbRatio", "index", "isf", "startTime", "status", "targetBG"].map { "profiles.profile[].tDependentSegs[].\($0)" })
        expected.formUnion(["autoShutdownDuration", "autoShutdownEnabled", "cannulaPrimeSize", "featureLock", "lowInsulinThreshold", "oledTimeout", "status"].map { "pumpSettings.\($0)" })
        for name in ["additionalBolusReminder", "afterBolusReminder", "highBGReminder", "lowBGReminder", "siteChangeReminder"] {
            expected.insert("reminders.\(name)")
            expected.formUnion(reminder.map { "reminders.\(name).\($0)" })
        }
        expected.insert("reminders.missedBolusReminder")
        expected.formUnion(reminder.map { "reminders.missedBolusReminder[].\($0)" })
        expected.formUnion([
            "annunProfile", "transmitterID", "sensorTimeoutDefaultBitmask", "sensorTimeoutEnabled", "sensorTimeoutMins",
            "fallRateAlertDefaultBitmask", "fallRateAlertEnabled", "fallRateAlertLevel",
            "riseRateAlertDefaultBitmask", "riseRateAlertEnabled", "riseRateAlertLevel",
            "highGlucoseAlertDefaultBitmask", "highGlucoseAlertDurationMins", "highGlucoseAlertEnabled", "highGlucoseAlertMgPerDl",
            "lowGlucoseAlertDefaultBitmask", "lowGlucoseAlertDurationMins", "lowGlucoseAlertEnabled", "lowGlucoseAlertMgPerDl",
        ].map { "cgmSettings.\($0)" })
        expected.formUnion(["ClosedLoop", "TotalDailyInsulin", "Weight", "WeightUnit"].map { "controlIQSettings.\($0)" })
        for i in 0 ..< 4 {
            expected.insert("controlIQSettings.SleepSchedule\(i)")
            expected.formUnion(sleep.map { "controlIQSettings.SleepSchedule\(i).\($0)" })
        }

        XCTAssertEqual(paths.subtracting(expected), [], "keys the iOS app doesn't send")
        XCTAssertEqual(expected.subtracting(paths), [], "keys the iOS app sends that are missing")
    }

    func testKeysAreSortedAsTheIOSAppEncodesThem() throws {
        let text = String(decoding: try TandemSourceSettings(reads()).encoded(), as: UTF8.self)
        let topLevel = ["basalLimitSettings", "cgmSettings", "controlIQSettings", "globalMaxBolusSettings", "globals", "localizationSettings", "profiles", "pumpSettings", "reminders"]
        let positions = topLevel.map { text.range(of: "\"\($0)\":")!.lowerBound }
        XCTAssertEqual(positions, positions.sorted())
    }

    func testProfileCarriesRawPumpValues() throws {
        let profiles = TandemSourceSettings(reads()).profiles
        XCTAssertEqual(profiles.activeIdp, 1)
        XCTAssertEqual(profiles.numberOfProfiles, 1)
        let profile = try XCTUnwrap(profiles.profile.first)
        XCTAssertEqual(profile.name, "Synthetic")
        XCTAssertEqual(profile.insulinDuration, 300)
        XCTAssertEqual(profile.maxBolus, 25000)
        XCTAssertEqual(profile.carbEntry, 1)
        let segment = try XCTUnwrap(profile.tDependentSegs.first)
        XCTAssertEqual(segment.basalRate, 800)
        XCTAssertEqual(segment.carbRatio, 10000)
        XCTAssertEqual(segment.targetBG, 110)
        XCTAssertEqual(segment.isf, 50)
    }

    func testNoActiveProfileReportsMinusOne() {
        var r = reads()
        r.profileStatus = ProfileStatusResponse(cargo: cargo(8, [0: [1], 1: [2, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]]))
        let profiles = TandemSourceSettings(r).profiles
        XCTAssertEqual(profiles.activeIdp, -1)
        XCTAssertEqual(profiles.activeSegment, -1)
    }

    func testSegmentStatusMovesBitFiveToBitFourAsTheAppSerializesIt() {
        XCTAssertEqual(TandemSourceSettings.Profiles.Segment.appStatus(0x3F), 0x1F)
        XCTAssertEqual(TandemSourceSettings.Profiles.Segment.appStatus(0x10), 0x00)
        XCTAssertEqual(TandemSourceSettings.Profiles.Segment.appStatus(0x2A), 0x1A)
    }

    func testOutOfRangeValuesTakeTheAppsCatchAllOrdinal() {
        let settings = TandemSourceSettings(reads())
        XCTAssertEqual(settings.globals.volumeSettings.buttonAnnun, 4)
        XCTAssertEqual(settings.localizationSettings?.languageSelected, 13)
        XCTAssertEqual(settings.cgmSettings.highGlucoseAlertDefaultBitmask, 0x07)
    }

    func testEmptyTransmitterIdIsSentAsTheAppsDefault() {
        XCTAssertEqual(TandemSourceSettings(reads()).cgmSettings.transmitterID, "000001")
        let named = cargo(17, [0: Array("ABC123".utf8), 16: [2]])
        let cgm = TandemSourceSettings(reads(hardwareInfo: named)).cgmSettings
        XCTAssertEqual(cgm.transmitterID, "ABC123")
        XCTAssertEqual(cgm.annunProfile, 2)
    }

    func testOptionalSectionsAreOmittedWhenThePumpDidNotAnswer() throws {
        var r = reads()
        r.basalLimit = nil
        r.globalMaxBolus = nil
        r.controlIQ = nil
        r.localization = nil
        let keys = Set(try json(TandemSourceSettings(r)).keys)
        XCTAssertEqual(keys, ["globals", "reminders", "pumpSettings", "cgmSettings", "profiles"])
    }

    func testSettingsUploadBodyCarriesSettingsAndNoEvents() throws {
        let info = TandemSourceDeviceInfo(serialNum: 1234567, modelNum: 1004000, partNum: 1, armSwVer: 1, mspSwVer: 0, pcbaSN: 1, configABits: 0, configBBits: 0, pumpRev: "0", pcbaRev: "0", pumpAPIVersion: "3.11", dexcomG6: true, basalIQ: false, controlIQ: true)
        let body = TandemSourceUploadBody(device: info, deviceAssignmentId: "assignment-uuid", settings: "e30=", now: Date(), pumpClock: Date())
        let decoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as! [String: Any]
        let data = ((decoded["package"] as! [String: Any])["device"] as! [String: Any])["data"] as! [String: Any]

        XCTAssertEqual(Set(data.keys), ["misc", "settings"])
        let features = (data["misc"] as! [String: Any])["pumpFeatures"] as! [String: Bool]
        XCTAssertEqual(features, ["dexcomG5": false, "dexcomG6": true, "freestyleLibre2": false, "freestyleLibre3": false, "basalIQ": false, "controlIQ": true])
    }
}
