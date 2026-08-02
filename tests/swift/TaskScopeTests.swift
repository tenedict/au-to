import XCTest

@testable import Whenly

/// 대시보드 사이드바가 보여 주는 묶음과 개수.
///
/// 화면이 이 계산을 하면 macOS·iOS·나중에 붙을 플랫폼이 각자 다르게 세고,
/// "오늘 3건" 이라고 적힌 자리와 눌러서 나오는 목록이 어긋난다.
final class TaskScopeTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_775_000_000)  // 2026-04-01 목요일 근처

    private func task(
        title: String,
        due: Date?,
        hasTime: Bool = false,
        completed: Bool = false
    ) -> AssistantTask {
        AssistantTask(
            title: title,
            dueDate: due,
            hasExplicitTime: hasTime,
            state: completed ? .completed : .pending
        )
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now) ?? now
    }

    // MARK: - 순서

    /// 사이드바 순서는 `DueBucket` 선언 순서를 그대로 따라야 한다.
    /// 여기서 다시 정렬하면 정렬 지점이 둘로 갈라지고, 홈 화면과 순서가 달라진다.
    func testScopeOrderFollowsBucketDeclarationOrder() {
        XCTAssertEqual(TaskScope.allCases.first, .all)
        XCTAssertEqual(
            Array(TaskScope.allCases.dropFirst()),
            DueBucket.allCases.map(TaskScope.due)
        )
    }

    // MARK: - 묶음별 목록

    func testEachBucketScopeReturnsOnlyItsOwnTasks() {
        let tasks = [
            task(title: "지난 마감", due: day(-3)),
            task(title: "오늘", due: now),
            task(title: "사흘 뒤", due: day(3)),
            task(title: "한 달 뒤", due: day(30)),
            task(title: "날짜 없음", due: nil),
            task(title: "끝냄", due: day(1), completed: true),
        ]

        func titles(_ bucket: DueBucket) -> [String] {
            TaskScoping.tasks(tasks, in: .due(bucket), now: now, calendar: calendar).map(\.title)
        }

        XCTAssertEqual(titles(.overdue), ["지난 마감"])
        XCTAssertEqual(titles(.today), ["오늘"])
        XCTAssertEqual(titles(.within7Days), ["사흘 뒤"])
        XCTAssertEqual(titles(.later), ["한 달 뒤"])
        XCTAssertEqual(titles(.someday), ["날짜 없음"])
        XCTAssertEqual(titles(.done), ["끝냄"])
    }

    // MARK: - 모든 할 일

    /// "모든 할 일" 은 완료를 빼고, 홈 화면과 **같은 급한 순**으로 이어져야 한다.
    /// 한 화면에서 본 순서가 다른 화면에서 바뀌면 사용자는 둘 중 하나를 못 믿게 된다.
    func testAllScopeExcludesDoneAndKeepsUrgencyOrder() {
        let tasks = [
            task(title: "한 달 뒤", due: day(30)),
            task(title: "날짜 없음", due: nil),
            task(title: "끝냄", due: day(1), completed: true),
            task(title: "오늘", due: now),
            task(title: "지난 마감", due: day(-3)),
            task(title: "사흘 뒤", due: day(3)),
        ]

        let titles = TaskScoping.tasks(tasks, in: .all, now: now, calendar: calendar).map(\.title)

        XCTAssertEqual(titles, ["지난 마감", "오늘", "사흘 뒤", "한 달 뒤", "날짜 없음"])
        XCTAssertFalse(titles.contains("끝냄"))
    }

    // MARK: - 개수

    /// 사이드바에 적히는 숫자는 눌렀을 때 나오는 목록의 길이와 반드시 같아야 한다.
    func testCountsMatchTheListsTheyLabel() {
        let tasks = [
            task(title: "지난 마감 1", due: day(-3)),
            task(title: "지난 마감 2", due: day(-1)),
            task(title: "오늘", due: now),
            task(title: "끝냄", due: day(1), completed: true),
        ]

        let counts = TaskScoping.counts(for: tasks, now: now, calendar: calendar)

        for scope in TaskScope.allCases {
            XCTAssertEqual(
                counts[scope],
                TaskScoping.tasks(tasks, in: scope, now: now, calendar: calendar).count,
                "\(scope.title) 의 개수가 목록 길이와 다릅니다"
            )
        }
        XCTAssertEqual(counts[.due(.overdue)], 2)
        XCTAssertEqual(counts[.due(.done)], 1)
        XCTAssertEqual(counts[.all], 3)
    }

    /// 할 일이 없어도 묶음은 사라지지 않는다.
    ///
    /// 홈 화면은 빈 묶음을 감추지만 사이드바는 감추면 안 된다 — 항목이 일하는 동안
    /// 나타났다 사라지면 누르려던 자리가 움직인다.
    func testEmptyScopesStillHaveAZeroCount() {
        let counts = TaskScoping.counts(for: [], now: now, calendar: calendar)

        XCTAssertEqual(counts.count, TaskScope.allCases.count)
        for scope in TaskScope.allCases {
            XCTAssertEqual(counts[scope], 0, "\(scope.title) 이 0 이 아닙니다")
        }
    }

    /// 시간이 명시된 할 일은 그 시각이 지나면 같은 날이라도 지난 마감이다.
    /// `DueGrouping` 의 규칙을 여기서 다시 구현하지 않았는지 확인한다.
    func testPassedTimeTodayCountsAsOverdueNotToday() {
        let twoHoursAgo = calendar.date(byAdding: .hour, value: -2, to: now) ?? now
        let tasks = [task(title: "오후 2시 예약", due: twoHoursAgo, hasTime: true)]

        let counts = TaskScoping.counts(for: tasks, now: now, calendar: calendar)

        XCTAssertEqual(counts[.due(.overdue)], 1)
        XCTAssertEqual(counts[.due(.today)], 0)
    }

    // MARK: - 요약

    /// 사이드바 최상단의 요약. 목록에 들어가기 전에 "지금 상태" 를 먼저 말한다
    /// (일기의 Insights 타일 · 디자인 연구 §6.3).
    func testSummaryCountsWhatNeedsAttentionNow() {
        let tasks = [
            task(title: "지난 마감 1", due: day(-3)),
            task(title: "지난 마감 2", due: day(-1)),
            task(title: "오늘", due: now),
            task(title: "사흘 뒤", due: day(3)),
            task(title: "끝냄", due: day(1), completed: true),
        ]

        let summary = TaskScoping.summary(for: tasks, now: now, calendar: calendar)

        XCTAssertEqual(summary.overdue, 2)
        XCTAssertEqual(summary.today, 1)
    }

    /// 요약의 숫자는 사이드바가 세는 숫자와 반드시 같아야 한다.
    /// 두 곳이 따로 세면 같은 화면에서 다른 값이 보인다.
    func testSummaryAgreesWithTheSidebarCounts() {
        let tasks = [
            task(title: "a", due: day(-2)), task(title: "b", due: day(-1)),
            task(title: "c", due: now), task(title: "d", due: day(2)),
        ]
        let counts = TaskScoping.counts(for: tasks, now: now, calendar: calendar)
        let summary = TaskScoping.summary(for: tasks, now: now, calendar: calendar)

        XCTAssertEqual(summary.overdue, counts[.due(.overdue)])
        XCTAssertEqual(summary.today, counts[.due(.today)])
    }

    /// 할 일이 없어도 요약은 0 으로 존재한다. 사라지면 자리가 움직인다.
    func testSummaryExistsWhenThereIsNothing() {
        let summary = TaskScoping.summary(for: [], now: now, calendar: calendar)
        XCTAssertEqual(summary.overdue, 0)
        XCTAssertEqual(summary.today, 0)
        XCTAssertTrue(summary.isClear, "아무것도 없으면 '비어 있음' 이어야 합니다")
    }

    /// 지난 마감이 하나라도 있으면 비어 있는 상태가 아니다.
    func testSummaryIsNotClearWhileSomethingIsOverdue() {
        let summary = TaskScoping.summary(
            for: [task(title: "지난 마감", due: day(-1))], now: now, calendar: calendar)
        XCTAssertFalse(summary.isClear)
    }
}
