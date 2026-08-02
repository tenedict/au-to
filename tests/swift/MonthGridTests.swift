import XCTest
@testable import Whenly

final class MonthGridTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 1  // 일요일 시작
        return calendar
    }()

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testEveryWeekHasSevenCells() {
        let grid = MonthGridBuilder.grid(containing: makeDate(2026, 8, 15), calendar: calendar)
        XCTAssertFalse(grid.weeks.isEmpty)
        XCTAssertTrue(grid.weeks.allSatisfy { $0.count == 7 })
    }

    func testGridContainsEveryDayOfTheMonthExactlyOnce() {
        let grid = MonthGridBuilder.grid(containing: makeDate(2026, 8, 15), calendar: calendar)
        let days = grid.days.map { calendar.component(.day, from: $0) }

        XCTAssertEqual(days, Array(1...31))
    }

    /// 2026-08-01 은 토요일이다. 일요일 시작 달력이면 앞에 빈칸이 여섯 개다.
    /// 이 계산이 어긋나면 모든 날짜가 한 칸씩 밀린 채 그려진다.
    func testLeadingBlanksMatchTheWeekdayOfTheFirstDay() {
        let grid = MonthGridBuilder.grid(containing: makeDate(2026, 8, 15), calendar: calendar)
        let firstWeek = grid.weeks[0]

        XCTAssertEqual(firstWeek.prefix(6).filter { $0 == nil }.count, 6)
        XCTAssertNotNil(firstWeek[6])
        XCTAssertEqual(calendar.component(.day, from: firstWeek[6]!), 1)
    }

    /// 주 시작 요일이 월요일인 로캘에서도 빈칸 수가 맞아야 한다.
    func testLeadingBlanksFollowFirstWeekday() {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        let grid = MonthGridBuilder.grid(containing: makeDate(2026, 8, 15), calendar: mondayFirst)

        // 토요일 시작 → 월요일 기준으로는 앞 빈칸이 다섯 개.
        XCTAssertEqual(grid.weeks[0].prefix(5).filter { $0 == nil }.count, 5)
        XCTAssertEqual(mondayFirst.component(.day, from: grid.weeks[0][5]!), 1)
    }

    func testFebruaryOfLeapYearHasTwentyNineDays() {
        let grid = MonthGridBuilder.grid(containing: makeDate(2028, 2, 10), calendar: calendar)
        XCTAssertEqual(grid.days.count, 29)
    }

    /// 12월에서 한 달 뒤는 다음 해 1월이다. 직접 +1 하면 13월이 된다.
    func testMonthOffsetCrossesYearBoundary() {
        let next = MonthGridBuilder.month(
            offsetting: makeDate(2026, 12, 20),
            by: 1,
            calendar: calendar
        )
        XCTAssertEqual(calendar.component(.year, from: next), 2027)
        XCTAssertEqual(calendar.component(.month, from: next), 1)
    }

    // MARK: - 날짜별 묶기

    func testTasksAreGroupedByStartOfDay() {
        let morning = makeDate(2026, 8, 10, 9)
        let evening = makeDate(2026, 8, 10, 21)
        let tasks = [
            AssistantTask(title: "아침", dueDate: morning, hasExplicitTime: true),
            AssistantTask(title: "저녁", dueDate: evening, hasExplicitTime: true),
            AssistantTask(title: "다른 날", dueDate: makeDate(2026, 8, 11, 9), hasExplicitTime: true)
        ]

        let byDay = MonthGridBuilder.tasksByDay(tasks, calendar: calendar)

        XCTAssertEqual(byDay[calendar.startOfDay(for: morning)]?.count, 2)
        XCTAssertEqual(byDay.count, 2)
    }

    func testUndatedTasksAreNotPlacedOnAnyDay() {
        let byDay = MonthGridBuilder.tasksByDay(
            [AssistantTask(title: "날짜 없음", dueDate: nil)],
            calendar: calendar
        )
        XCTAssertTrue(byDay.isEmpty)
    }

    /// 종일 할 일이 위, 시간이 있는 것은 이른 시각부터.
    func testAllDayTasksComeBeforeTimedTasks() {
        let day = makeDate(2026, 8, 10, 0)
        let tasks = [
            AssistantTask(title: "3시", dueDate: makeDate(2026, 8, 10, 15), hasExplicitTime: true),
            AssistantTask(title: "종일", dueDate: day, hasExplicitTime: false),
            AssistantTask(title: "9시", dueDate: makeDate(2026, 8, 10, 9), hasExplicitTime: true)
        ]

        let byDay = MonthGridBuilder.tasksByDay(tasks, calendar: calendar)

        XCTAssertEqual(
            byDay[calendar.startOfDay(for: day)]?.map(\.title),
            ["종일", "9시", "3시"]
        )
    }
}
