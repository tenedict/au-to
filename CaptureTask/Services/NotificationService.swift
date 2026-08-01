import Foundation
// UNUserNotificationCenter 는 Sendable 로 표시돼 있지 않지만 실제로는 스레드 안전하다.
// 표시가 붙을 때까지 여기서 넘어간다 — 경고를 남겨 두면 새 경고가 묻힌다.
@preconcurrency import UserNotifications

/// 마감 알림 예약. 언제 보낼지는 `ReminderSchedule` 이 계산하고, 여기서는 거는 일만 한다.
protocol TaskReminderScheduling: Sendable {
    /// 권한을 물은 적이 없으면 묻는다. 이미 거절했으면 다시 묻지 않는다.
    func requestAuthorizationIfNeeded() async -> Bool
    /// 이 할 일의 알림을 전부 지우고 지금 기준으로 다시 건다.
    func reschedule(_ task: AssistantTask, now: Date) async
    /// 이 할 일의 알림을 전부 지운다.
    func cancel(taskID: UUID) async
    /// 앱이 켜질 때 전체를 맞춘다. 알림이 없는 사이 마감이 지났을 수 있다.
    func syncAll(_ tasks: [AssistantTask], now: Date) async
    /// 지금 권한 상태. 화면이 "왜 알림이 안 오는지"를 말할 수 있어야 한다.
    func authorizationState() async -> ReminderAuthorizationState
}

enum ReminderAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied

    /// 비활성 컨트롤에 함께 보여줄 이유 (AGENTS 규칙 9).
    var explanation: String? {
        switch self {
        case .notDetermined:
            return "처음 저장할 때 알림 권한을 여쭤볼게요."
        case .authorized:
            return nil
        case .denied:
            return "알림이 꺼져 있어요. 설정 > 알림 > CaptureTask에서 켜 주세요."
        }
    }
}

struct LocalNotificationService: TaskReminderScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        switch await authorizationState() {
        case .authorized:
            return true
        case .denied:
            // 여기서 다시 물어도 시스템이 보여주지 않는다. 화면이 설정으로 안내한다.
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge]))
                ?? false
        }
    }

    func authorizationState() async -> ReminderAuthorizationState {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    func reschedule(_ task: AssistantTask, now: Date = .now) async {
        // 항상 먼저 전부 지운다. 마감을 앞당겼는데 예전 알림이 남으면
        // 이미 끝낸 일로 한 번 더 울린다.
        await cancel(taskID: task.id)

        for plan in ReminderSchedule.plans(for: task, now: now) {
            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = plan.kind.body
            content.sound = .default
            content.userInfo = ["taskID": task.id.uuidString]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: plan.fireAt
            )
            let request = UNNotificationRequest(
                identifier: ReminderSchedule.identifier(taskID: task.id, kind: plan.kind),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func cancel(taskID: UUID) async {
        center.removePendingNotificationRequests(
            withIdentifiers: ReminderSchedule.allIdentifiers(taskID: taskID)
        )
    }

    func syncAll(_ tasks: [AssistantTask], now: Date = .now) async {
        for task in tasks {
            await reschedule(task, now: now)
        }
    }
}

/// 테스트와 미리보기용. 알림을 실제로 걸지 않고 요청만 기록한다.
final class RecordingReminderScheduler: TaskReminderScheduling, @unchecked Sendable {
    private(set) var scheduled: [UUID: [ReminderPlan]] = [:]
    private(set) var cancelled: [UUID] = []
    var state: ReminderAuthorizationState = .authorized

    func requestAuthorizationIfNeeded() async -> Bool { state == .authorized }

    func authorizationState() async -> ReminderAuthorizationState { state }

    func reschedule(_ task: AssistantTask, now: Date) async {
        cancelled.append(task.id)
        scheduled[task.id] = ReminderSchedule.plans(for: task, now: now)
    }

    func cancel(taskID: UUID) async {
        cancelled.append(taskID)
        scheduled[taskID] = nil
    }

    func syncAll(_ tasks: [AssistantTask], now: Date) async {
        for task in tasks {
            await reschedule(task, now: now)
        }
    }
}
