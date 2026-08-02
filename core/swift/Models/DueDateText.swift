import Foundation

/// 마감을 적을 자리의 폭.
///
/// **형식은 자리의 폭이 정한다.** 같은 날짜라도 월 격자의 한 칸과 확인 화면의 한 줄에
/// 같은 글자를 넣을 수는 없다. Apple 캘린더도 한 화면에서 날짜를 셋으로 다르게 적는다 —
/// 주 스트립은 숫자만, 머리글은 완전 서술, 시각 알약은 시각만
/// (디자인 연구 §5.2).
enum DueDateWidth: String, CaseIterable, Sendable {
    /// 월 격자의 날짜 칸. 숫자만.
    case tick
    /// 접힌 카드의 마감 · 목록 행 · 사이드바. **한 줄을 넘으면 안 된다.**
    case narrow
    /// 펼친 카드 · 일별 일정 머리글. 요일을 더한다.
    case medium
    /// 확인 화면 · 캘린더 날짜 머리글 · 알림 문구. 모호함이 없어야 한다.
    case full
}

/// 마감을 글자로 옮긴다. 전부 순수 함수다.
///
/// **이 파일이 날짜 형식을 만드는 유일한 자리다.** 화면은 등급만 고른다.
/// 형식이 화면마다 흩어지면 좁은 자리에도 완전 서술형이 들어가고, 두 줄이 되어
/// 접힌 카드에서 잘린다 — 실제로 그렇게 잘렸다 (개발 보고서 §9.1).
///
/// `now` 는 언제나 인자다. 안에서 `.now` 를 읽으면 "오늘" 이 오늘 날짜에 따라
/// 흔들려 테스트가 어제와 오늘 다른 결과를 낸다.
enum DueDateText {

    /// 좁음 등급이 넘지 않아야 하는 글자 수.
    ///
    /// 한 줄에 들어가는지는 결국 그리는 폭에 달렸지만, 형식이 조용히 길어지는 것은
    /// 여기서 막을 수 있다. 지금 가장 긴 결과는 `2027년 3월 2일 오후 11:59` 다.
    static let narrowCharacterLimit = 24

    static func string(
        for date: Date?,
        hasExplicitTime: Bool,
        width: DueDateWidth,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        guard let date else {
            // 날짜가 없다는 사실 자체가 사용자가 해야 할 일이다.
            return width == .tick ? "" : "날짜 확인 필요"
        }

        switch width {
        case .tick:
            return numberFormatter.string(from: NSNumber(value: calendar.component(.day, from: date)))
                ?? ""
        case .narrow:
            return narrow(date, hasExplicitTime: hasExplicitTime, now: now, calendar: calendar)
        case .medium:
            return join(
                dayWithWeekdayInParens(date, calendar: calendar),
                time(date, hasExplicitTime: hasExplicitTime, calendar: calendar))
        case .full:
            return full(date, hasExplicitTime: hasExplicitTime, now: now, calendar: calendar)
        }
    }

    // MARK: - 등급별

    /// 가까운 날은 상대어로, 이번 주는 요일로, 같은 해는 연도 없이.
    ///
    /// 좁은 자리에서 연도는 대개 이미 아는 정보다. 반대로 다른 해의 날짜에서
    /// 연도를 빼면 사용자가 1년을 잘못 읽는다 — 그건 지워도 되는 정보가 아니다.
    private static func narrow(
        _ date: Date, hasExplicitTime: Bool, now: Date, calendar: Calendar
    ) -> String {
        let clock = time(date, hasExplicitTime: hasExplicitTime, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let dayDiff = calendar.dateComponents([.day], from: today, to: day).day ?? 0

        switch dayDiff {
        case 0: return join("오늘", clock)
        case -1: return join("어제", clock)
        case 1: return join("내일", clock)
        case 2...6:
            // 이번 주 안이면 요일 하나로 어느 날인지 정해진다.
            return join(weekday(date, calendar: calendar), clock)
        default:
            let sameYear =
                calendar.component(.year, from: date) == calendar.component(.year, from: now)
            let base =
                sameYear
                ? monthDay(date, calendar: calendar)
                : yearMonthDay(date, calendar: calendar)
            return join(base, clock)
        }
    }

    private static func full(
        _ date: Date, hasExplicitTime: Bool, now: Date, calendar: Calendar
    ) -> String {
        let clock = time(date, hasExplicitTime: hasExplicitTime, calendar: calendar)
        let body = join(
            join(yearMonthDay(date, calendar: calendar), weekday(date, calendar: calendar)),
            clock)
        // 완전 등급에서도 "오늘" 은 알려 준다. 다만 날짜를 지우지는 않는다 —
        // 확인 화면에서 사용자가 판단하는 근거는 날짜 자체다.
        guard calendar.isDate(date, inSameDayAs: now) else { return body }
        return "오늘 · " + body
    }

    // MARK: - 등급 밖의 두 가지

    /// 달의 이름 — `2026년 8월`.
    ///
    /// 날짜가 아니라 **달**이라 폭 등급에 들어가지 않는다. 다만 형식을 만드는 자리는
    /// 여기 하나여야 하므로 함께 둔다.
    static func monthTitle(for date: Date, calendar: Calendar = .current) -> String {
        formatter(calendar) { $0.setLocalizedDateFormatFromTemplate("yMMMM") }.string(from: date)
    }

    /// 하루 안에서의 시각 — `오후 6:00` 또는 `종일`.
    ///
    /// 날짜가 이미 머리글에 있는 자리(일별 일정)에서 쓴다. 시각이 없으면 빈칸이 아니라
    /// **종일**이라고 말한다 — 빈칸은 "아직 안 정했다" 로 읽힌다.
    static func clock(
        for date: Date?, hasExplicitTime: Bool, calendar: Calendar = .current
    ) -> String {
        guard let date, hasExplicitTime else { return "종일" }
        return formatter(calendar) { $0.timeStyle = .short }.string(from: date)
    }

    // MARK: - 조각

    private static func join(_ lhs: String, _ rhs: String) -> String {
        guard !rhs.isEmpty else { return lhs }
        guard !lhs.isEmpty else { return rhs }
        return lhs + " " + rhs
    }

    /// 시각은 마감에 시각이 있을 때만 붙인다.
    ///
    /// 종일 할 일에 "오전 12:00" 을 붙이면 자정에 무슨 일이 있는 것처럼 읽힌다.
    private static func time(_ date: Date, hasExplicitTime: Bool, calendar: Calendar) -> String {
        guard hasExplicitTime else { return "" }
        return formatter(calendar) { $0.timeStyle = .short }.string(from: date)
    }

    private static func monthDay(_ date: Date, calendar: Calendar) -> String {
        formatter(calendar) { $0.setLocalizedDateFormatFromTemplate("MMMMd") }.string(from: date)
    }

    private static func yearMonthDay(_ date: Date, calendar: Calendar) -> String {
        formatter(calendar) { $0.setLocalizedDateFormatFromTemplate("yMMMMd") }.string(from: date)
    }

    private static func weekday(_ date: Date, calendar: Calendar) -> String {
        formatter(calendar) { $0.setLocalizedDateFormatFromTemplate("EEEE") }.string(from: date)
    }

    /// `8월 5일 (수)` — 보통 등급에서 요일을 괄호로 덧붙인다.
    private static func dayWithWeekdayInParens(_ date: Date, calendar: Calendar) -> String {
        let short = formatter(calendar) { $0.setLocalizedDateFormatFromTemplate("EEEEE") }
            .string(from: date)
        return monthDay(date, calendar: calendar) + " (" + short + ")"
    }

    // MARK: - 도구

    /// `DateFormatter` 는 만드는 비용이 크다. 다만 달력·로캘·시간대가 인자로 오므로
    /// 하나를 재사용할 수 없다 — 대신 설정만 매번 다시 건다.
    private static func formatter(
        _ calendar: Calendar, _ configure: (DateFormatter) -> Void
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? Locale(identifier: "ko_KR")
        formatter.timeZone = calendar.timeZone
        configure(formatter)
        return formatter
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        // "20일" 이 아니라 "20". 격자 한 칸에는 숫자만 들어간다.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
