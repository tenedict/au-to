import Foundation

/// 대시보드 사이드바가 보여 주는 묶음.
///
/// 마감 묶음(`DueBucket`)에 "모든 할 일" 하나를 더한 것이다. 순서는 `DueBucket`
/// 선언 순서를 그대로 따른다 — 급한 것이 위다. 여기서 다시 정렬하면 정렬 지점이
/// 둘로 갈라지고, 홈 화면과 사이드바의 순서가 달라진다.
///
/// 화면이 아니라 여기서 세는 이유는, macOS 와 iOS 가 각자 세면 "오늘 3건" 이라고
/// 적힌 자리와 눌러서 나오는 목록이 어긋나기 때문이다.
enum TaskScope: Hashable, Sendable, Identifiable {
    /// 완료하지 않은 할 일 전부. 묶음을 고르기 전의 기본 자리다.
    case all
    case due(DueBucket)

    /// 사이드바에 그릴 순서 그대로.
    static let allCases: [TaskScope] = [.all] + DueBucket.allCases.map(TaskScope.due)

    var id: String {
        switch self {
        case .all: return "all"
        case .due(let bucket): return bucket.rawValue
        }
    }

    var title: String {
        switch self {
        case .all: return "모든 할 일"
        case .due(let bucket): return bucket.title
        }
    }

    /// 색만으로 상태를 전달하지 않기 위한 기호 (CLAUDE 규칙 13).
    var symbolName: String {
        switch self {
        case .all: return "tray.full"
        case .due(let bucket): return bucket.symbolName
        }
    }
}

/// 묶음별로 할 일을 고르고 센다. 전부 순수 함수다.
///
/// `now` 는 언제나 인자다. 안에서 `.now` 를 읽으면 테스트가 오늘 날짜에 따라 흔들린다.
enum TaskScoping {

    /// 그 묶음에 속하는 할 일. 묶음 안의 순서는 `DueGrouping` 이 정한 것을 그대로 쓴다.
    static func tasks(
        _ tasks: [AssistantTask],
        in scope: TaskScope,
        now: Date,
        calendar: Calendar = .current
    ) -> [AssistantTask] {
        switch scope {
        case .all:
            // "모든 할 일" 도 급한 순이어야 한다. 묶음을 만들어 이어 붙이면
            // 홈 화면과 순서가 저절로 같아진다 — 여기서 다시 정렬하지 않는다.
            let open = tasks.filter { !$0.isCompleted }
            return DueGrouping.groups(for: open, now: now, calendar: calendar).flatMap(\.tasks)
        case .due(let bucket):
            let members = tasks.filter {
                DueGrouping.bucket(for: $0, now: now, calendar: calendar) == bucket
            }
            return DueGrouping.sorted(members, in: bucket)
        }
    }

    /// 사이드바에 적히는 숫자.
    ///
    /// 할 일이 없는 묶음도 0 으로 남긴다. 항목이 일하는 동안 나타났다 사라지면
    /// 누르려던 자리가 움직인다 — 홈 화면이 빈 묶음을 감추는 것과는 다른 판단이다.
    static func counts(
        for tasks: [AssistantTask],
        now: Date,
        calendar: Calendar = .current
    ) -> [TaskScope: Int] {
        var result: [TaskScope: Int] = [:]
        for scope in TaskScope.allCases {
            result[scope] = self.tasks(tasks, in: scope, now: now, calendar: calendar).count
        }
        return result
    }
}
