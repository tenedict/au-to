import Foundation

/// 마감 알림 한 건의 종류. 알림 식별자에 들어가므로 `rawValue` 를 바꾸면
/// 이미 예약된 알림을 취소하지 못한다.
enum ReminderKind: String, CaseIterable, Codable, Sendable {
    /// 마감 하루 전 저녁 — 준비할 시간을 준다.
    case dayBeforeEvening
    /// 종일 할 일의 마감 당일 아침 — 하루를 시작할 때 한 번.
    case morningOfDueDay
    /// 시간이 명시된 할 일의 1시간 전 — 이동이 필요한 것에 맞춘다.
    case oneHourBefore

    var body: String {
        switch self {
        case .dayBeforeEvening: return "내일 마감이에요"
        case .morningOfDueDay: return "오늘 마감이에요"
        case .oneHourBefore: return "한 시간 뒤예요"
        }
    }
}

struct ReminderPlan: Equatable, Sendable {
    let kind: ReminderKind
    let fireAt: Date
}

/// 마감 알림을 언제 보낼지 계산한다. 순수 함수다 — `UNUserNotificationCenter` 를 모른다.
///
/// 알림 시각을 서비스 안에서 계산하면 검증하려고 실제 알림을 예약해야 한다.
/// 그러면 아무도 검증하지 않게 되고, 사용자는 안 오는 알림을 기다린다.
enum ReminderSchedule {

    /// 종일 할 일의 마감 당일 알림 시각.
    static let morningHour = 9
    /// 마감 하루 전 알림 시각.
    static let eveningHour = 20
    /// 시간이 명시된 할 일의 사전 알림 간격.
    static let leadTimeBeforeExplicitTime: TimeInterval = 60 * 60

    /// 지금 예약해야 할 알림들. 이른 것부터.
    ///
    /// 이미 지난 시각은 넣지 않는다. 지난 알림을 예약하면 iOS 가 조용히 버리거나
    /// 즉시 울린다 — 둘 다 사용자에게는 고장으로 읽힌다.
    static func plans(
        for task: AssistantTask,
        now: Date,
        calendar: Calendar = .current
    ) -> [ReminderPlan] {
        guard !task.isCompleted, task.wantsReminders, let dueDate = task.dueDate else {
            return []
        }

        var candidates: [ReminderPlan] = []

        if task.hasExplicitTime {
            candidates.append(
                ReminderPlan(
                    kind: .oneHourBefore,
                    fireAt: dueDate.addingTimeInterval(-leadTimeBeforeExplicitTime)
                )
            )
        } else if let morning = calendar.date(
            bySettingHour: morningHour,
            minute: 0,
            second: 0,
            of: dueDate
        ) {
            candidates.append(ReminderPlan(kind: .morningOfDueDay, fireAt: morning))
        }

        if let previousDay = calendar.date(byAdding: .day, value: -1, to: dueDate),
           let evening = calendar.date(
               bySettingHour: eveningHour,
               minute: 0,
               second: 0,
               of: previousDay
           ) {
            candidates.append(ReminderPlan(kind: .dayBeforeEvening, fireAt: evening))
        }

        return candidates
            .filter { $0.fireAt > now }
            .sorted { $0.fireAt < $1.fireAt }
    }

    /// 알림 식별자. 취소는 이 문자열로만 한다.
    ///
    /// 할 일 하나가 알림 여러 건을 갖기 때문에 `taskID` 만으로는 취소 대상을 못 고른다.
    static func identifier(taskID: UUID, kind: ReminderKind) -> String {
        "\(taskID.uuidString)#\(kind.rawValue)"
    }

    /// 한 할 일이 가질 수 있는 모든 식별자. 마감이 바뀌면 이 전부를 지우고 다시 건다.
    static func allIdentifiers(taskID: UUID) -> [String] {
        ReminderKind.allCases.map { identifier(taskID: taskID, kind: $0) }
    }
}
