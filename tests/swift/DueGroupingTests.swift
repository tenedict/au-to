import XCTest
@testable import CaptureTask

/// 홈 화면의 순서를 고정한다.
///
/// 화면을 눈으로 보고 "대충 맞네" 로 넘기면, 마감이 지난 할 일이 조용히 아래로 내려가도
/// 아무도 모른다. 순서는 계약이므로 숫자로 잡는다.
final class DueGroupingTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    /// 2026-08-01 (토) 14:00. 모든 테스트가 같은 "지금"을 쓴다.
    private let now = Date(timeIntervalSince1970: 1_785_909_600)

    private func makeTask(
        title: String = "할 일",
        due: Date?,
        hasExplicitTime: Bool = false,
        completed: Bool = false,
        createdAt: Date = Date(timeIntervalSince1970: 1_785_000_000)
    ) -> AssistantTask {
        AssistantTask(
            title: title,
            dueDate: due,
            hasExplicitTime: hasExplicitTime,
            state: completed ? .completed : .pending,
            createdAt: createdAt
        )
    }

    private func date(offsetDays: Int, hour: Int = 12) -> Date {
        let day = calendar.date(byAdding: .day, value: offsetDays, to: now)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    // MARK: - 분류

    func testYesterdayIsOverdue() {
        let bucket = DueGrouping.bucket(
            for: makeTask(due: date(offsetDays: -1)),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(bucket, .overdue)
    }

    func testTodayIsToday() {
        let bucket = DueGrouping.bucket(
            for: makeTask(due: date(offsetDays: 0, hour: 23)),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(bucket, .today)
    }

    /// 시간이 명시된 할 일은 같은 날이라도 그 시각이 지나면 이미 늦은 것이다.
    /// 날짜만 비교하면 "오후 2시 예약"이 오후 6시에도 오늘 할 일로 남는다.
    func testTodayWithPassedExplicitTimeIsOverdue() {
        let passed = calendar.date(byAdding: .hour, value: -2, to: now)!
        let bucket = DueGrouping.bucket(
            for: makeTask(due: passed, hasExplicitTime: true),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(bucket, .overdue)
    }

    /// 종일 할 일은 시각이 없으므로 하루가 끝날 때까지 오늘이다.
    func testTodayAllDayStaysTodayEvenInTheEvening() {
        let midnight = calendar.startOfDay(for: now)
        let bucket = DueGrouping.bucket(
            for: makeTask(due: midnight, hasExplicitTime: false),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(bucket, .today)
    }

    func testSevenDaysAheadIsWithin7DaysAndEightIsLater() {
        XCTAssertEqual(
            DueGrouping.bucket(for: makeTask(due: date(offsetDays: 7)), now: now, calendar: calendar),
            .within7Days
        )
        XCTAssertEqual(
            DueGrouping.bucket(for: makeTask(due: date(offsetDays: 8)), now: now, calendar: calendar),
            .later
        )
    }

    func testTaskWithoutDateIsSomeday() {
        XCTAssertEqual(
            DueGrouping.bucket(for: makeTask(due: nil), now: now, calendar: calendar),
            .someday
        )
    }

    /// 완료한 할 일은 마감이 지났어도 `지난 마감` 에 올라오지 않는다.
    /// 끝낸 일이 계속 급한 것으로 보이면 목록 전체를 믿지 않게 된다.
    func testCompletedTaskLeavesOverdueEvenIfPastDue() {
        XCTAssertEqual(
            DueGrouping.bucket(
                for: makeTask(due: date(offsetDays: -3), completed: true),
                now: now,
                calendar: calendar
            ),
            .done
        )
    }

    // MARK: - 순서

    func testGroupsAppearInUrgencyOrder() {
        let tasks = [
            makeTask(title: "나중", due: date(offsetDays: 20)),
            makeTask(title: "날짜없음", due: nil),
            makeTask(title: "오늘", due: date(offsetDays: 0)),
            makeTask(title: "지남", due: date(offsetDays: -2)),
            makeTask(title: "이번주", due: date(offsetDays: 3)),
            makeTask(title: "완료", due: date(offsetDays: 1), completed: true)
        ]

        let buckets = DueGrouping.groups(for: tasks, now: now, calendar: calendar).map(\.bucket)

        XCTAssertEqual(buckets, [.overdue, .today, .within7Days, .later, .someday, .done])
    }

    func testEmptyBucketsAreNotShown() {
        let groups = DueGrouping.groups(
            for: [makeTask(due: date(offsetDays: 0))],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(groups.map(\.bucket), [.today])
    }

    /// 가장 오래 밀린 것이 제일 급하다. 지난 마감도 이른 것이 위다.
    func testOverdueIsSortedOldestFirst() {
        let tasks = [
            makeTask(title: "하루 지남", due: date(offsetDays: -1)),
            makeTask(title: "닷새 지남", due: date(offsetDays: -5)),
            makeTask(title: "이틀 지남", due: date(offsetDays: -2))
        ]

        let group = DueGrouping.groups(for: tasks, now: now, calendar: calendar).first
        XCTAssertEqual(group?.tasks.map(\.title), ["닷새 지남", "이틀 지남", "하루 지남"])
    }

    func testDatedBucketIsSortedByNearestDeadline() {
        let tasks = [
            makeTask(title: "6일 뒤", due: date(offsetDays: 6)),
            makeTask(title: "2일 뒤", due: date(offsetDays: 2)),
            makeTask(title: "4일 뒤", due: date(offsetDays: 4))
        ]

        let group = DueGrouping.groups(for: tasks, now: now, calendar: calendar).first
        XCTAssertEqual(group?.tasks.map(\.title), ["2일 뒤", "4일 뒤", "6일 뒤"])
    }

    func testSomedayIsSortedNewestFirst() {
        let old = makeTask(title: "예전", due: nil, createdAt: Date(timeIntervalSince1970: 1_000))
        let new = makeTask(title: "최근", due: nil, createdAt: Date(timeIntervalSince1970: 2_000))

        let group = DueGrouping.groups(for: [old, new], now: now, calendar: calendar).first
        XCTAssertEqual(group?.tasks.map(\.title), ["최근", "예전"])
    }

    func testUpcomingSkipsCompletedAndUndatedTasks() {
        let tasks = [
            makeTask(title: "완료", due: date(offsetDays: 1), completed: true),
            makeTask(title: "날짜없음", due: nil),
            makeTask(title: "예정", due: date(offsetDays: 2))
        ]

        XCTAssertEqual(DueGrouping.upcoming(tasks).map(\.title), ["예정"])
    }
}
