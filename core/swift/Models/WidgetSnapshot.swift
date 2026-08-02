import Foundation

/// 위젯이 한 번 그리는 데 필요한 것 전부.
///
/// **파생 값을 저장하지 않는다** (CLAUDE 규칙 14). 위젯 전용 파일을 따로 쓰면
/// 할 일이 바뀔 때마다 두 곳을 맞춰야 하고, 반드시 한 곳이 뒤처진다 — 그러면
/// 홈 화면 위젯만 지난주 일정을 계속 보여준다.
///
/// 그래서 위젯도 **같은 원장**(`tasks.json`)을 읽고, 묶고 정렬하는 것은 앱과 **같은
/// 순수 함수**(`DueGrouping`)에 맡긴다. App Group 안에 있으므로 확장이 그대로 읽는다.
struct WidgetSnapshot {
    /// 앞으로 올 것들. 급한 순서다.
    let upcoming: [AssistantTask]
    /// 지난 마감 개수. 목록에는 넣지 않고 숫자만 쓴다 —
    /// 좁은 위젯에서 지난 것이 앞자리를 다 먹으면 "다음 일정" 이 안 보인다.
    let overdueCount: Int
    /// 오늘 몫.
    let todayCount: Int
    /// 읽지 못한 이유. 위젯은 빈 것과 못 읽은 것을 다르게 말해야 한다.
    ///
    /// **`try?` 로 삼키지 않는다** (CLAUDE 규칙 8). 위젯에는 경고창이 없지만
    /// 화면은 있다 — 읽지 못한 이유가 여기까지 올라와야 사용자가 "아직 할 일이
    /// 없는 것" 과 "App Group 설정이 틀린 것" 을 구별할 수 있다.
    let unavailableReason: String?

    var isUnavailable: Bool { unavailableReason != nil }

    static func unavailable(_ reason: String) -> WidgetSnapshot {
        WidgetSnapshot(
            upcoming: [], overdueCount: 0, todayCount: 0, unavailableReason: reason)
    }

    var isEmpty: Bool { upcoming.isEmpty && overdueCount == 0 }

    /// 원장에서 지금 상태를 읽는다.
    ///
    /// - Parameter limit: 가장 큰 위젯이 필요로 하는 만큼만. 전부 들고 있어 봐야
    ///   위젯이 그릴 수 있는 줄 수는 정해져 있다.
    static func read(now: Date, limit: Int = 8) -> WidgetSnapshot {
        let tasks: [AssistantTask]
        do {
            tasks = try TaskStorage.makeDefault().loadTasks()
        } catch {
            return .unavailable(error.localizedDescription)
        }

        let groups = DueGrouping.groups(for: tasks, now: now)
        let overdue = groups.first { $0.bucket == .overdue }?.tasks ?? []
        let today = groups.first { $0.bucket == .today }?.tasks ?? []
        // 날짜 없음(`someday`)과 완료는 빼고 세운다. "다음 일정" 을 묻는 위젯에
        // 날짜 없는 것을 넣으면 언제나 목록 끝에 붙어 자리만 먹는다.

        // 지난 마감을 목록 맨 앞에 둔다 — 위에 있을수록 급하다는 규칙은
        // 위젯에서도 같다. 다만 개수는 따로 세어 배지로도 말한다.
        let upcoming = groups
            .filter { $0.bucket != .done && $0.bucket != .someday }
            .flatMap(\.tasks)

        return WidgetSnapshot(
            upcoming: Array(upcoming.prefix(limit)),
            overdueCount: overdue.count,
            todayCount: today.count,
            unavailableReason: nil)
    }

    /// 위젯 갤러리에서 보여줄 예시.
    ///
    /// **빈 화면을 보여주지 않는다.** 갤러리에서 빈 위젯을 본 사용자는 그것이
    /// 고장인지 아직 할 일이 없어서인지 구별할 수 없고, 대개 담지 않는다.
    static func placeholder(now: Date) -> WidgetSnapshot {
        WidgetSnapshot(
            upcoming: [
                AssistantTask(
                    title: "치과 정기 검진",
                    dueDate: now.addingTimeInterval(60 * 60 * 3),
                    hasExplicitTime: true),
                AssistantTask(
                    title: "장학금 서류 제출",
                    dueDate: now.addingTimeInterval(60 * 60 * 26),
                    hasExplicitTime: true),
                AssistantTask(
                    title: "전기요금 자동이체 확인",
                    dueDate: now.addingTimeInterval(60 * 60 * 72)),
            ],
            overdueCount: 0,
            todayCount: 1,
            unavailableReason: nil)
    }
}

/// 위젯이 다시 그려질 시각을 정한다.
///
/// 시스템은 하루에 몇 번만 위젯을 깨워 준다. 그래서 **분 단위로 다시 그리라고
/// 조르지 않는다** — 대신 "지금 상태가 바뀌는 순간" 을 골라 그때 깨워 달라고 한다.
/// 할 일이 바뀔 때는 앱이 `WidgetCenter` 로 직접 깨운다.
enum WidgetRefresh {

    /// 다음에 다시 그려야 할 시각.
    ///
    /// 가장 가까운 마감이 지나는 순간이 곧 화면이 바뀌는 순간이다 — "1시간 뒤" 가
    /// "지난 마감" 으로 바뀐다. 그 시각이 없으면 자정에 한 번 (오늘이 어제가 된다).
    static func next(after now: Date, snapshot: WidgetSnapshot, calendar: Calendar = .current)
        -> Date
    {
        let midnight = calendar.startOfDay(for: now.addingTimeInterval(24 * 60 * 60))
        let nextDue = snapshot.upcoming
            .compactMap(\.dueDate)
            .filter { $0 > now }
            .min()
        guard let nextDue else { return midnight }
        return min(nextDue, midnight)
    }
}
