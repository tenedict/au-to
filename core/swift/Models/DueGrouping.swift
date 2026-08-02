import Foundation

/// 홈 화면의 마감 묶음. 위에 있을수록 급하다.
///
/// 순서를 `CaseIterable` 선언 순서에 의존시킨다. 화면이 정렬을 다시 하지 않는다 —
/// 정렬 지점이 둘로 갈라지면 "왜 이게 위에 있지"를 아무도 설명하지 못하게 된다.
enum DueBucket: String, CaseIterable, Codable, Sendable {
    case overdue
    case today
    case within7Days
    case later
    case someday
    case done

    var title: String {
        switch self {
        case .overdue: return "지난 마감"
        case .today: return "오늘"
        case .within7Days: return "앞으로 7일"
        case .later: return "그 뒤"
        case .someday: return "날짜 없음"
        case .done: return "완료"
        }
    }

    /// 색만으로 상태를 전달하지 않기 위한 기호 (AGENTS 규칙 10).
    var symbolName: String {
        switch self {
        case .overdue: return "exclamationmark.triangle.fill"
        case .today: return "sun.max.fill"
        case .within7Days: return "calendar"
        case .later: return "clock"
        case .someday: return "questionmark.circle"
        case .done: return "checkmark.circle.fill"
        }
    }

    /// 처음부터 접어 두는 묶음. 급하지 않은 것이 화면을 먹지 않게 한다.
    var startsCollapsed: Bool {
        self == .later || self == .someday || self == .done
    }
}

struct DueGroup: Identifiable, Equatable, Sendable {
    let bucket: DueBucket
    let tasks: [AssistantTask]

    var id: DueBucket { bucket }
    var count: Int { tasks.count }
}

/// 마감 묶음 분류와 정렬. 전부 순수 함수다.
///
/// 뷰가 `now` 를 직접 읽으면 테스트가 오늘 날짜에 따라 흔들린다. `now` 는 언제나 인자다.
enum DueGrouping {

    /// 하루 앞을 "이번 주"로 볼 것인가의 경계. 오늘로부터 이 일수까지가 `within7Days`.
    static let soonWindowDays = 7

    static func bucket(
        for task: AssistantTask,
        now: Date,
        calendar: Calendar = .current
    ) -> DueBucket {
        if task.isCompleted { return .done }
        guard let dueDate = task.dueDate else { return .someday }

        // 시간이 명시된 할 일은 그 시각이 지나면 같은 날이라도 이미 늦은 것이다.
        // 날짜만 비교하면 "오후 2시 예약"이 오후 6시에도 오늘 할 일로 남는다.
        if task.hasExplicitTime, dueDate < now { return .overdue }

        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: dueDate)
        guard let dayDiff = calendar.dateComponents([.day], from: today, to: dueDay).day else {
            return .someday
        }

        switch dayDiff {
        case ..<0: return .overdue
        case 0: return .today
        case 1...soonWindowDays: return .within7Days
        default: return .later
        }
    }

    /// 화면에 그릴 순서 그대로 묶어 돌려준다. 빈 묶음은 넣지 않는다.
    static func groups(
        for tasks: [AssistantTask],
        now: Date,
        calendar: Calendar = .current
    ) -> [DueGroup] {
        var bucketed: [DueBucket: [AssistantTask]] = [:]
        for task in tasks {
            bucketed[bucket(for: task, now: now, calendar: calendar), default: []].append(task)
        }

        return DueBucket.allCases.compactMap { bucket in
            guard let members = bucketed[bucket], !members.isEmpty else { return nil }
            return DueGroup(bucket: bucket, tasks: sorted(members, in: bucket))
        }
    }

    /// 묶음 안에서의 순서.
    ///
    /// 마감이 있는 묶음은 이른 것이 위다. `지난 마감` 도 같다 — 가장 오래 밀린 것이
    /// 제일 급하기 때문이다. 마감이 없으면 최근에 만든 것이 위다.
    static func sorted(_ tasks: [AssistantTask], in bucket: DueBucket) -> [AssistantTask] {
        switch bucket {
        case .someday:
            return tasks.sorted { $0.createdAt > $1.createdAt }
        case .done:
            return tasks.sorted { $0.createdAt > $1.createdAt }
        default:
            return tasks.sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (l?, r?) where l != r: return l < r
                case (nil, _?): return false
                case (_?, nil): return true
                default: return lhs.createdAt < rhs.createdAt
                }
            }
        }
    }

    /// 마감이 있는 미완료 할 일만, 이른 순으로. 캘린더 뷰와 알림 재동기화가 쓴다.
    static func upcoming(_ tasks: [AssistantTask]) -> [AssistantTask] {
        tasks
            .filter { !$0.isCompleted && $0.dueDate != nil }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
}
