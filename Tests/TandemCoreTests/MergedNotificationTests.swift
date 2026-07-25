@testable import TandemCore
import XCTest

/// Verifies that co-firing pump notifications are merged into a single UI row,
/// including groups that span categories. The first modelled group is
/// `RESUME_PUMP_ALARM` (18) + `RESUME_PUMP_ALARM2` (23).
final class MergedNotificationTests: XCTestCase {
    private typealias Member = MergedNotificationGroup.Member

    /// Creates a bitmask from the given bit positions (raw values).
    private func bitmask(_ positions: Int...) -> UInt64 {
        positions.reduce(0) { $0 | (1 << $1) }
    }

    private let resumeAlarm = AlarmStatusResponse.AlarmResponseType.RESUME_PUMP_ALARM.rawValue // 18
    private let resumeAlarm2 = AlarmStatusResponse.AlarmResponseType.RESUME_PUMP_ALARM2.rawValue // 23

    // MARK: - Catalog

    /// The resume-pump alarms are declared as a merged group, with the
    /// lower-numbered alarm as the primary.
    func testCatalogContainsResumePumpGroup() {
        let expectedMembers: [Member] = [.alarm(.RESUME_PUMP_ALARM), .alarm(.RESUME_PUMP_ALARM2)]
        let group = MergedNotification.groups.first { $0.members == expectedMembers }
        XCTAssertNotNil(group)
        XCTAssertEqual(group?.primary, Member.alarm(.RESUME_PUMP_ALARM))
    }

    /// Guards the configured pairs against typos/regressions.
    func testCatalogContainsAllConfiguredPairs() {
        let expected: [[Member]] = [
            [.alarm(.RESUME_PUMP_ALARM), .alarm(.RESUME_PUMP_ALARM2)],
            [.alarm(.OCCLUSION_ALARM), .alarm(.OCCLUSION_ALARM2)],
            [.alert(.MIN_BASAL_ALERT), .alert(.MIN_BASAL_ALERT2)],
            [.alert(.LOW_POWER_ALERT), .alert(.LOW_POWER_ALERT2)],
            [.alert(.LOW_INSULIN_ALERT), .alert(.LOW_INSULIN_ALERT2)],
            [.alert(.CONNECTION_ERROR_ALERT), .alert(.CONNECTION_ERROR_ALERT2)]
        ]
        for members in expected {
            XCTAssertTrue(
                MergedNotification.groups.contains { $0.members == members },
                "Missing merged group: \(members)"
            )
        }
    }

    // MARK: - Primary selection

    /// When no primary is specified, the first declared member is primary.
    func testPrimaryDefaultsToFirstMember() {
        let group = MergedNotificationGroup(members: [Member(type: .alarm, id: 40), Member(type: .alarm, id: 41)])
        XCTAssertEqual(group.primary, Member(type: .alarm, id: 40))
    }

    /// An explicit primary can be any member and is independent of position.
    func testExplicitPrimaryIsHonored() {
        let group = MergedNotificationGroup(
            members: [Member(type: .alarm, id: 40), Member(type: .alarm, id: 41)],
            primary: Member(type: .alarm, id: 41)
        )
        XCTAssertEqual(group.primary, Member(type: .alarm, id: 41))
    }

    /// The primary supplies the description shown and the id dismissed, and is
    /// listed first in the merged row — even when it is not the first member.
    func testPrimaryDeterminesDescriptionAndDismissalId() {
        let first = NotificationItem(type: .alarm, id: 40, name: "ALARM_A", notificationDescription: "Description A.")
        let second = NotificationItem(type: .alarm, id: 41, name: "ALARM_B", notificationDescription: "Description B.")
        // members list A first, but B is nominated primary.
        let group = MergedNotificationGroup(
            members: [Member(type: .alarm, id: 40), Member(type: .alarm, id: 41)],
            primary: Member(type: .alarm, id: 41)
        )

        let merged = MergedNotification.merge([first, second], using: [group])
        XCTAssertEqual(merged.count, 1)
        // Description + dismissal id come from the primary (B).
        XCTAssertEqual(merged[0].notificationId, 41)
        XCTAssertEqual(merged[0].displayTitle, "Description B.")
        // Primary is listed first, the remaining member follows.
        XCTAssertEqual(merged[0].categoryTitle, "Alarm: ALARM_B, ALARM_A")
        XCTAssertEqual(merged[0].mergedNames, ["ALARM_A"])
    }

    // MARK: - Cross-category merging

    /// A group may span categories. The merged row takes the primary's category,
    /// description, and id, and the label re-prefixes at the category boundary.
    func testCrossCategoryGroupMergesAlertAndAlarm() {
        let alarm = NotificationItem(type: .alarm, id: 5, name: "SOME_ALARM", notificationDescription: "Alarm text.")
        let alert = NotificationItem(type: .alert, id: 5, name: "SOME_ALERT", notificationDescription: "Alert text.")
        // Same raw id (5) in two categories; the alert is nominated primary.
        let group = MergedNotificationGroup(
            members: [Member(type: .alarm, id: 5), Member(type: .alert, id: 5)],
            primary: Member(type: .alert, id: 5)
        )

        let merged = MergedNotification.merge([alarm, alert], using: [group])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].type, .alert)
        XCTAssertEqual(merged[0].notificationId, 5)
        XCTAssertEqual(merged[0].displayTitle, "Alert text.")
        XCTAssertEqual(merged[0].categoryTitle, "Alert: SOME_ALERT, Alarm: SOME_ALARM")
        // The alarm member is retained (with its own type + id) for dismissal.
        XCTAssertEqual(merged[0].mergedMembers, [
            NotificationItem.MergedMember(type: .alarm, id: 5, name: "SOME_ALARM")
        ])
    }

    /// Only declared groups merge: with just the resume-alarm group in the catalog,
    /// an alert sharing a raw id with a grouped alarm is left as its own row
    /// (members match on category + id, not id alone).
    func testUndeclaredCrossCategoryPairIsNotMerged() {
        let bundle = NotificationBundle()
        bundle.add(AlarmStatusResponse(intMap: bitmask(resumeAlarm, resumeAlarm2)))
        // Alert bit 18 shares the raw id of RESUME_PUMP_ALARM but is not grouped.
        bundle.add(AlertStatusResponse(intMap: bitmask(resumeAlarm)))

        let alarmRows = bundle.get().filter { $0.type == .alarm }
        let alertRows = bundle.get().filter { $0.type == .alert }
        XCTAssertEqual(alarmRows.count, 1)
        XCTAssertEqual(alarmRows[0].categoryTitle, "Alarm: RESUME_PUMP_ALARM, RESUME_PUMP_ALARM2")
        XCTAssertEqual(alertRows.count, 1)
    }

    // MARK: - Bundle-level behaviour

    /// Both resume-pump alarms collapse into one row whose category line lists both
    /// member names, in declared order.
    func testResumePumpAlarmsMergeIntoSingleRow() {
        let bundle = NotificationBundle()
        bundle.add(AlarmStatusResponse(intMap: bitmask(resumeAlarm, resumeAlarm2)))

        let items = bundle.get()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(bundle.getNotificationCount(), 1)

        let item = items[0]
        XCTAssertEqual(item.type, .alarm)
        XCTAssertEqual(item.categoryTitle, "Alarm: RESUME_PUMP_ALARM, RESUME_PUMP_ALARM2")
        XCTAssertEqual(item.mergedNames, ["RESUME_PUMP_ALARM2"])
        // The primary (lower id) drives dismissal; the pump acks the rest.
        XCTAssertEqual(item.notificationId, UInt32(resumeAlarm))
        // The shared description is preserved from the primary.
        XCTAssertEqual(item.displayTitle, "Insulin delivery is currently off. Please restart insulin delivery soon.")
    }

    /// Alert pairs merge too (not just alarms): both low-insulin alerts collapse
    /// into a single Alert row.
    func testAlertPairMergesIntoSingleRow() {
        let bundle = NotificationBundle()
        // LOW_INSULIN_ALERT (0) + LOW_INSULIN_ALERT2 (17)
        bundle.add(AlertStatusResponse(intMap: bitmask(0, 17)))

        let items = bundle.get()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .alert)
        XCTAssertEqual(items[0].categoryTitle, "Alert: LOW_INSULIN_ALERT, LOW_INSULIN_ALERT2")
        XCTAssertEqual(items[0].displayTitle, "Low amount of insulin remaining in the cartridge.")
        XCTAssertEqual(items[0].notificationId, 0)
    }

    /// A lone member does not merge — it renders as its own ordinary row. This is
    /// also the graceful fallback if the pump only partially acknowledges a group.
    func testLoneResumePumpAlarmIsNotMerged() {
        let bundle = NotificationBundle()
        bundle.add(AlarmStatusResponse(intMap: bitmask(resumeAlarm2)))

        let items = bundle.get()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].categoryTitle, "Alarm: RESUME_PUMP_ALARM2")
        XCTAssertEqual(items[0].mergedNames, [])
        XCTAssertEqual(items[0].notificationId, UInt32(resumeAlarm2))
    }

    /// Unrelated alarms are untouched, and the merged row keeps the position of its
    /// first present member (so ordering by raw value is preserved).
    func testUnrelatedAlarmsAreUnaffectedAndOrderingIsStable() {
        let bundle = NotificationBundle()
        // bit 2 = OCCLUSION_ALARM, plus the two resume alarms.
        bundle.add(AlarmStatusResponse(intMap: bitmask(2, resumeAlarm, resumeAlarm2)))

        let items = bundle.get()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].categoryTitle, "Alarm: OCCLUSION_ALARM")
        XCTAssertEqual(items[1].categoryTitle, "Alarm: RESUME_PUMP_ALARM, RESUME_PUMP_ALARM2")
    }

    // MARK: - isActive

    /// `isActive` reflects the raw per-category state and never confuses categories
    /// that share a raw id — the check the dismissal reload relies on.
    func testIsActiveReflectsBundleContents() {
        let bundle = NotificationBundle()
        bundle.add(AlarmStatusResponse(intMap: bitmask(resumeAlarm)))

        XCTAssertTrue(bundle.isActive(type: .alarm, id: UInt32(resumeAlarm)))
        XCTAssertFalse(bundle.isActive(type: .alarm, id: UInt32(resumeAlarm2)))
        // Same numeric id, different category → not active.
        XCTAssertFalse(bundle.isActive(type: .alert, id: UInt32(resumeAlarm)))
    }

    // MARK: - Merge unit behaviour

    /// Items that do not complete a group are left unchanged: a lone group member
    /// (one occlusion alarm without its pair) and an ungrouped reminder.
    func testItemsThatDoNotCompleteAGroupAreUnchanged() {
        let items = [
            NotificationItem(type: .alarm, id: 2, name: "OCCLUSION_ALARM"),
            NotificationItem(type: .reminder, id: 3, name: "SITE_CHANGE_REMINDER")
        ]
        let merged = MergedNotification.merge(items)
        XCTAssertEqual(merged.map(\.categoryTitle), items.map(\.categoryTitle))
    }
}
