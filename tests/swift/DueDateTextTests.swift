import XCTest

@testable import Whenly

/// 마감을 글자로 옮기는 규칙.
///
/// 형식이 화면마다 흩어져 있으면 좁은 자리에도 완전 서술형이 들어가고, 그러면
/// 두 줄이 되어 접힌 카드에서 잘린다 — 실제로 그렇게 잘렸다.
/// **형식은 자리의 폭이 정한다** (디자인 언어 §9).
final class DueDateTextTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.locale = Locale(identifier: "ko_KR")
        return calendar
    }()

    /// 2026-08-03 (월) 12:00 KST
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 12))!
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0)
        -> Date
    {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func text(
        _ date: Date?, time: Bool = false, _ width: DueDateWidth
    ) -> String {
        DueDateText.string(
            for: date, hasExplicitTime: time, width: width, now: now, calendar: calendar)
    }

    // MARK: - 눈금

    /// 월 격자는 숫자만 쓴다. 맥락은 머리글이 준다.
    func testTickIsTheDayNumberOnly() {
        XCTAssertEqual(text(date(2026, 8, 5), .tick), "5")
        XCTAssertEqual(text(date(2026, 12, 25), .tick), "25")
    }

    // MARK: - 좁음 · 상대 표기

    func testNarrowUsesRelativeWordsForNearbyDays() {
        XCTAssertEqual(text(date(2026, 8, 3), .narrow), "오늘")
        XCTAssertEqual(text(date(2026, 8, 2), .narrow), "어제")
        XCTAssertEqual(text(date(2026, 8, 4), .narrow), "내일")
    }

    /// 이번 주 안이면 요일 하나로 충분하다.
    func testNarrowUsesWeekdayWithinTheWeek() {
        // 2026-08-07 은 금요일
        XCTAssertEqual(text(date(2026, 8, 7), .narrow), "금요일")
    }

    func testNarrowDropsTheYearWithinTheSameYear() {
        let narrow = text(date(2026, 9, 15), .narrow)
        XCTAssertEqual(narrow, "9월 15일")
        XCTAssertFalse(narrow.contains("년"), "같은 해에는 연도를 적지 않는다")
    }

    func testNarrowKeepsTheYearForAnotherYear() {
        XCTAssertEqual(text(date(2027, 3, 2), .narrow), "2027년 3월 2일")
    }

    /// 시각은 마감에 시각이 있을 때만 붙인다.
    func testNarrowAppendsTimeOnlyWhenExplicit() {
        XCTAssertEqual(text(date(2026, 8, 3, 18), time: false, .narrow), "오늘")
        XCTAssertTrue(text(date(2026, 8, 3, 18), time: true, .narrow).hasPrefix("오늘 "))
        XCTAssertTrue(text(date(2026, 8, 3, 18), time: true, .narrow).count > 2)
    }

    // MARK: - 보통 · 완전

    func testMediumAddsTheWeekday() {
        XCTAssertEqual(text(date(2026, 8, 5), .medium), "8월 5일 (수)")
    }

    func testFullNeverDropsTheYear() {
        let full = text(date(2026, 8, 5), .full)
        XCTAssertTrue(full.contains("2026년"), "완전 등급은 연도를 생략하지 않는다: \(full)")
        XCTAssertTrue(full.contains("수요일"))
    }

    /// 오늘이라는 사실은 완전 등급에서도 알려 준다. 다만 날짜를 함께 적는다.
    func testFullMarksTodayButStillShowsTheDate() {
        let full = text(date(2026, 8, 3), .full)
        XCTAssertTrue(full.hasPrefix("오늘 · "), full)
        XCTAssertTrue(full.contains("2026년 8월 3일"), full)
    }

    // MARK: - 날짜 없음

    func testMissingDateSaysWhatToDo() {
        for width in DueDateWidth.allCases where width != .tick {
            XCTAssertEqual(text(nil, width), "날짜 확인 필요", "\(width)")
        }
        XCTAssertEqual(text(nil, .tick), "")
    }

    // MARK: - 계약

    /// 좁음은 한 줄에 들어가야 한다. 줄바꿈이 들어가면 접힌 카드에서 잘린다.
    func testNarrowNeverContainsALineBreak() {
        let samples: [Date] = [
            date(2026, 8, 3, 18), date(2026, 8, 2), date(2026, 8, 4, 9),
            date(2026, 8, 7), date(2026, 9, 15, 14, 30), date(2027, 3, 2, 23, 59),
            date(2025, 1, 1),
        ]
        for sample in samples {
            for time in [true, false] {
                let narrow = text(sample, time: time, .narrow)
                XCTAssertFalse(narrow.contains("\n"), narrow)
                XCTAssertLessThanOrEqual(
                    narrow.count, DueDateText.narrowCharacterLimit,
                    "좁음이 \(narrow.count)자입니다 — 한 줄을 넘길 수 있습니다: \(narrow)")
            }
        }
    }

    /// 등급이 넓어질수록 길어진다. 좁음이 완전보다 길면 등급의 뜻이 뒤집힌다.
    func testWiderGradesAreNotShorter() {
        let sample = date(2026, 9, 15, 14, 30)
        let narrow = text(sample, time: true, .narrow)
        let medium = text(sample, time: true, .medium)
        let full = text(sample, time: true, .full)
        XCTAssertLessThanOrEqual(narrow.count, medium.count, "\(narrow) / \(medium)")
        XCTAssertLessThanOrEqual(medium.count, full.count, "\(medium) / \(full)")
    }

    /// `now` 를 인자로 받는다. 안에서 읽으면 테스트가 오늘 날짜에 따라 흔들린다.
    func testRelativeWordsFollowTheGivenNow() {
        let laterNow = date(2026, 8, 10, 12)
        let result = DueDateText.string(
            for: date(2026, 8, 3), hasExplicitTime: false,
            width: .narrow, now: laterNow, calendar: calendar)
        XCTAssertEqual(result, "8월 3일", "기준 시각이 바뀌면 '오늘' 이 아니어야 합니다")
    }
}

/// 접힌 카드의 노출 계약 (디자인 언어 §10.4).
///
/// 적층은 "접힌 카드는 상단 일부만 보인다" 를 전제한다. 노출 높이는 고정이고
/// 그 안에 들어가야 하는 내용은 가변이라, **계약을 코드가 지켜야 한다.**
final class CardPeekContractTests: XCTestCase {

    /// C-1 · 노출 높이 안에 제목 1행과 마감 1행이 들어간다.
    func testPeekHeightHoldsTitleAndDueDate() {
        XCTAssertLessThanOrEqual(
            CardMetrics.peekContentHeight, CardMetrics.peekHeight,
            "노출 영역(\(CardMetrics.peekHeight)pt) 안에 내용"
                + "(\(CardMetrics.peekContentHeight)pt)이 들어가지 않습니다")
    }

    /// C-3 · 가려지는 영역이 실제로 존재한다. 없다면 적층이 아니라 목록이다.
    func testCollapsedCardIsTallerThanItsPeek() {
        XCTAssertGreaterThan(CardMetrics.collapsedHeight, CardMetrics.peekHeight)
    }

    /// 적층 배치가 노출 높이를 그대로 쓴다. 두 값이 갈라지면 겹침이 어긋난다.
    func testStackLayoutUsesTheSamePeekHeight() {
        XCTAssertEqual(WalletStackLayout.default.peekHeight, CardMetrics.peekHeight)
        XCTAssertEqual(WalletStackLayout.default.collapsedHeight, CardMetrics.collapsedHeight)
    }
}
