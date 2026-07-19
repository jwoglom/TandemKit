@testable import TandemCore
import XCTest

/// Verifies that co-firing pump notifications the pump acknowledges together are
/// merged into a single UI row. The first modelled group is
/// `RESUME_PUMP_ALARM` (18) + `RESUME_PUMP_ALARM2` (23).
final class MergedNotificationTests: XCTestCase {
    /// Creates a bitmask from the given bit positions (raw values).
    private func bitmask(_ positions: Int...) -> UInt64 {
        positions.reduce(0) { $0 | (1 << $1) }
    }

    private let resumeAlarm = AlarmStatusResponse.AlarmResponseType.RESUME_PUMP_ALARM.rawValue // 18
    private let resumeAlarm2 = AlarmStatusResponse.AlarmResponseType.RESUME_PUMP_ALARM2.rawValue // 23

    // MARK: - Catalog

    /// The resume-pump alarms are declared as a merged group scoped to alarms, with
    /// the lower-numbered alarm as the primary.
    func testCatalogContainsResumePumpGroup() {
        let group = MergedNotification.groups.first {
            $0.type == .alarm && $0.members.contains(UInt32(resumeAlarm))
        }
        XCTAssertNotNil(group)
        XCTAssertEqual(group?.members, [UInt32(resumeAlarm), UInt32(resumeAlarm2)])
        XCTAssertEqual(group?.primary, UInt32(resumeAlarm))
    }

    // MARK: - Primary selection

    /// When no primary is specified, the first declared member is primary.
    func testPrimaryDefaultsToFirstMember() {
        let group = MergedNotificationGroup(type: .alarm, members: [40, 41])
        XCTAssertEqual(group.primary, 40)
    }

    /// An explicit primary can be any member and is independent of position.
    func testExplicitPrimaryIsHonored() {
        let group = MergedNotificationGroup(type: .alarm, members: [40, 41], primary: 41)
        XCTAssertEqual(group.primary, 41)
    }

    /// The primary supplies the description shown and the id dismissed, and is
    /// listed first in the merged row — even when it is not the first member.
    func testPrimaryDeterminesDescriptionAndDismissalId() {
        let first = NotificationItem(type: .alarm, id: 40, name: "ALARM_A", notificationDescription: "Description A.")
        let second = NotificationItem(type: .alarm, id: 41, name: "ALARM_B", notificationDescription: "Description B.")
        // members list A first, but B is nominated primary.
        let group = MergedNotificationGroup(type: .alarm, members: [40, 41], primary: 41)

        let merged = MergedNotification.merge([first, second], using: [group])
        XCTAssertEqual(merged.count, 1)
        // Description + dismissal id come from the primary (B).
        XCTAssertEqual(merged[0].notificationId, 41)
        XCTAssertEqual(merged[0].displayTitle, "Description B.")
        // Primary is listed first, the remaining member follows.
        XCTAssertEqual(merged[0].categoryTitle, "Alarm: ALARM_B, ALARM_A")
        XCTAssertEqual(merged[0].mergedNames, ["ALARM_A"])
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

    /// Merging does not reach across categories: an alert sharing a raw value with a
    /// grouped alarm is left alone.
    func testMergingDoesNotSpanCategories() {
        let bundle = NotificationBundle()
        bundle.add(AlarmStatusResponse(intMap: bitmask(resumeAlarm, resumeAlarm2)))
        // Alert bit 18 is an unrelated alert; it must remain its own row.
        bundle.add(AlertStatusResponse(intMap: bitmask(resumeAlarm)))

        let alarmRows = bundle.get().filter { $0.type == .alarm }
        let alertRows = bundle.get().filter { $0.type == .alert }
        XCTAssertEqual(alarmRows.count, 1)
        XCTAssertEqual(alarmRows[0].categoryTitle, "Alarm: RESUME_PUMP_ALARM, RESUME_PUMP_ALARM2")
        XCTAssertEqual(alertRows.count, 1)
    }

    // MARK: - Merge unit behaviour

    /// The pure merge leaves a list with no grouped members unchanged.
    func testMergeIsIdentityWithoutGroups() {
        let items = [
            NotificationItem(type: .alarm, id: 2, name: "OCCLUSION_ALARM"),
            NotificationItem(type: .reminder, id: 3, name: "SITE_CHANGE_REMINDER")
        ]
        let merged = MergedNotification.merge(items)
        XCTAssertEqual(merged.map(\.categoryTitle), items.map(\.categoryTitle))
    }
}
