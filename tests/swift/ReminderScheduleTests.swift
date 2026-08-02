import XCTest
@testable import Whenly

/// 알림 시각 계약.
///
/// 시간 지정 할 일은 1시간 전, 종일 할 일은 당일 09:00, 공통으로 하루 전 20:00.
/// 이 숫자가 흔들리면 사용자는 "안 오는 알림"을 기다린다 — 눈으로는 절대 못 잡는다.
final class ReminderScheduleTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0)
        -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    private func makeTask(
        due: Date?,
        hasExplicitTime: Bool,
        completed: Bool = false,
        remindersEnabled: Bool? = nil
    ) -> AssistantTask {
        AssistantTask(
            title: "치과 예약",
            dueDate: due,
            hasExplicitTime: hasExplicitTime,
            state: completed ? .completed : .pending,
            remindersEnabled: remindersEnabled
        )
    }

    // MARK: - 시간이 명시된 할 일

    func testExplicitTimeSchedulesOneHourBeforeAndPreviousEvening() {
        let due = makeDate(2026, 8, 10, 14, 30)
        let now = makeDate(2026, 8, 1, 9)

        let plans = ReminderSchedule.plans(
            for: makeTask(due: due, hasExplicitTime: true),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plans.map(\.kind), [.dayBeforeEvening, .oneHourBefore])
        XCTAssertEqual(plans[0].fireAt, makeDate(2026, 8, 9, 20))
        XCTAssertEqual(plans[1].fireAt, makeDate(2026, 8, 10, 13, 30))
    }

    // MARK: - 종일 할 일

    func testAllDayTaskSchedulesMorningOfDueDayAndPreviousEvening() {
        let due = makeDate(2026, 8, 10, 0)
        let now = makeDate(2026, 8, 1, 9)

        let plans = ReminderSchedule.plans(
            for: makeTask(due: due, hasExplicitTime: false),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plans.map(\.kind), [.dayBeforeEvening, .morningOfDueDay])
        XCTAssertEqual(plans[0].fireAt, makeDate(2026, 8, 9, 20))
        XCTAssertEqual(plans[1].fireAt, makeDate(2026, 8, 10, 9))
    }

    func testAllDayTaskDoesNotGetOneHourBeforeReminder() {
        let plans = ReminderSchedule.plans(
            for: makeTask(due: makeDate(2026, 8, 10, 0), hasExplicitTime: false),
            now: makeDate(2026, 8, 1, 9),
            calendar: calendar
        )
        XCTAssertFalse(plans.contains { $0.kind == .oneHourBefore })
    }

    // MARK: - 지난 시각은 걸지 않는다

    /// 지난 시각을 예약하면 iOS 가 조용히 버리거나 즉시 울린다. 둘 다 고장으로 읽힌다.
    func testPastFireTimesAreDropped() {
        // 마감 당일 오전 11시. 하루 전 20:00 과 당일 09:00 은 이미 지났다.
        let plans = ReminderSchedule.plans(
            for: makeTask(due: makeDate(2026, 8, 10, 0), hasExplicitTime: false),
            now: makeDate(2026, 8, 10, 11),
            calendar: calendar
        )
        XCTAssertTrue(plans.isEmpty)
    }

    func testOnlyFutureReminderSurvivesWhenTodayMorningPassed() {
        // 마감 오늘 18:00, 지금 15:00 → 1시간 전(17:00)만 남는다.
        let plans = ReminderSchedule.plans(
            for: makeTask(due: makeDate(2026, 8, 10, 18), hasExplicitTime: true),
            now: makeDate(2026, 8, 10, 15),
            calendar: calendar
        )
        XCTAssertEqual(plans.map(\.kind), [.oneHourBefore])
        XCTAssertEqual(plans[0].fireAt, makeDate(2026, 8, 10, 17))
    }

    // MARK: - 걸지 않는 경우

    func testNoRemindersWithoutDueDate() {
        XCTAssertTrue(
            ReminderSchedule.plans(
                for: makeTask(due: nil, hasExplicitTime: false),
                now: makeDate(2026, 8, 1, 9),
                calendar: calendar
            ).isEmpty
        )
    }

    func testCompletedTaskGetsNoReminders() {
        XCTAssertTrue(
            ReminderSchedule.plans(
                for: makeTask(due: makeDate(2026, 8, 10, 14), hasExplicitTime: true, completed: true),
                now: makeDate(2026, 8, 1, 9),
                calendar: calendar
            ).isEmpty
        )
    }

    func testRemindersCanBeTurnedOff() {
        XCTAssertTrue(
            ReminderSchedule.plans(
                for: makeTask(
                    due: makeDate(2026, 8, 10, 14),
                    hasExplicitTime: true,
                    remindersEnabled: false
                ),
                now: makeDate(2026, 8, 1, 9),
                calendar: calendar
            ).isEmpty
        )
    }

    /// 예전에 저장한 할 일에는 이 필드가 없다. 없으면 알림을 켠 것으로 본다.
    func testMissingRemindersFlagDefaultsToOn() {
        XCTAssertFalse(
            ReminderSchedule.plans(
                for: makeTask(
                    due: makeDate(2026, 8, 10, 14),
                    hasExplicitTime: true,
                    remindersEnabled: nil
                ),
                now: makeDate(2026, 8, 1, 9),
                calendar: calendar
            ).isEmpty
        )
    }

    // MARK: - 식별자

    /// 취소는 식별자로만 한다. 한 할 일이 알림 여러 건을 갖기 때문에
    /// 종류별로 구분되지 않으면 일부만 지워진다.
    func testIdentifiersAreUniquePerKind() {
        let taskID = UUID()
        let identifiers = ReminderSchedule.allIdentifiers(taskID: taskID)

        XCTAssertEqual(identifiers.count, ReminderKind.allCases.count)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(identifiers.allSatisfy { $0.hasPrefix(taskID.uuidString) })
    }
}
