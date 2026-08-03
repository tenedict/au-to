import EventKit
import Foundation

/// 캘린더에 쓰는 일.
///
/// **프로토콜 뒤에 두는 이유는 테스트다.** 저장소가 `CalendarService()` 를 직접
/// 만들면 단위 테스트가 EventKit 권한을 실제로 요청하고, 시뮬레이터에는 그걸
/// 눌러 줄 사람이 없어 **각 호출이 몇 분씩 멈춘다** — 실제로 180건짜리 스위트가
/// 583초 걸렸다. 밀리초 단위여야 할 것이다.
@MainActor
protocol CalendarWriting: Sendable {
    @discardableResult
    func addToCalendar(_ task: AssistantTask) async throws -> String
    func updateEvent(identifier: String, with task: AssistantTask) async throws
    func removeFromCalendar(eventIdentifier: String) async
}

/// 테스트와 미리보기용. 아무것도 쓰지 않고 요청만 기록한다.
@MainActor
final class RecordingCalendarService: CalendarWriting {
    private(set) var added: [AssistantTask] = []
    private(set) var updated: [String] = []
    private(set) var removed: [String] = []
    /// 캘린더가 실패하는 상황을 재현할 때 켠다.
    var failure: Error?

    func addToCalendar(_ task: AssistantTask) async throws -> String {
        if let failure { throw failure }
        added.append(task)
        return "event-\(added.count)"
    }

    func updateEvent(identifier: String, with task: AssistantTask) async throws {
        if let failure { throw failure }
        updated.append(identifier)
    }

    func removeFromCalendar(eventIdentifier: String) async {
        removed.append(eventIdentifier)
    }
}

/// Apple 캘린더는 **출력**이지 원장이 아니다.
///
/// 할 일의 소유권은 언제나 앱에 있다. 캘린더 쓰기가 실패해도 할 일은 저장된 상태로 남는다
/// (AGENTS 규칙 6). 그래서 이 서비스는 저장 성공/실패만 돌려주고 상태를 갖지 않는다.
@MainActor
final class CalendarService: CalendarWriting {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    /// 캘린더에 넣고 이벤트 식별자를 돌려준다.
    @discardableResult
    func addToCalendar(_ task: AssistantTask) async throws -> String {
        guard let dueDate = task.dueDate else {
            throw CalendarServiceError.missingDate
        }
        guard try await requestAccessIfNeeded() else {
            throw CalendarServiceError.accessDenied
        }
        // 기본 캘린더가 없는 계정 구성이 실제로 있다. 여기서 막지 않으면
        // save 가 알아듣기 어려운 EventKit 오류를 던진다.
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw CalendarServiceError.missingCalendar
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = task.title
        event.notes = task.notes
        event.startDate = dueDate
        event.isAllDay = !task.hasExplicitTime
        event.endDate = task.hasExplicitTime
            ? dueDate.addingTimeInterval(60 * 60)
            : Calendar.current.date(byAdding: .day, value: 1, to: dueDate) ?? dueDate

        try eventStore.save(event, span: .thisEvent)
        guard let identifier = event.eventIdentifier else {
            throw CalendarServiceError.missingIdentifier
        }
        return identifier
    }

    /// 이미 들어가 있는 일정을 고친 내용으로 맞춘다.
    ///
    /// **지우고 다시 넣지 않는다.** 그러면 식별자가 바뀌어 사용자가 캘린더 앱에서
    /// 걸어 둔 알림이나 초대가 함께 날아간다.
    ///
    /// 사용자가 캘린더 앱에서 이미 지운 경우에는 새로 만들지 않고 그 사실을 알린다 —
    /// 여기서 조용히 다시 만들면 지운 사람의 뜻을 되돌리는 것이 된다.
    func updateEvent(identifier: String, with task: AssistantTask) async throws {
        guard let dueDate = task.dueDate else {
            throw CalendarServiceError.missingDate
        }
        guard try await requestAccessIfNeeded() else {
            throw CalendarServiceError.accessDenied
        }
        guard let event = eventStore.event(withIdentifier: identifier) else {
            throw CalendarServiceError.missingEvent
        }

        event.title = task.title
        event.notes = task.notes
        event.startDate = dueDate
        event.isAllDay = !task.hasExplicitTime
        event.endDate = task.hasExplicitTime
            ? dueDate.addingTimeInterval(60 * 60)
            : Calendar.current.date(byAdding: .day, value: 1, to: dueDate) ?? dueDate

        try eventStore.save(event, span: .thisEvent)
    }

    /// 할 일을 지울 때 캘린더에서도 거둔다.
    ///
    /// 실패해도 던지지 않는다. 이벤트를 사용자가 캘린더 앱에서 이미 지웠을 수 있고,
    /// 그 때문에 할 일 삭제가 막히면 안 된다.
    func removeFromCalendar(eventIdentifier: String) async {
        guard (try? await requestAccessIfNeeded()) == true else { return }
        guard let event = eventStore.event(withIdentifier: eventIdentifier) else { return }
        try? eventStore.remove(event, span: .thisEvent)
    }

    private func requestAccessIfNeeded() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return try await eventStore.requestWriteOnlyAccessToEvents()
        @unknown default:
            return false
        }
    }
}

enum CalendarServiceError: LocalizedError {
    case missingDate
    case accessDenied
    case missingCalendar
    case missingIdentifier
    case missingEvent

    var errorDescription: String? {
        switch self {
        case .missingDate:
            return "날짜가 없어 캘린더에 추가할 수 없어요."
        case .missingEvent:
            return "캘린더에서 이 일정을 찾지 못했어요. 캘린더 앱에서 지운 것 같아요."
        case .accessDenied:
            return "캘린더 접근이 꺼져 있어요. 설정 > Whenly에서 접근을 허용해 주세요."
        case .missingCalendar:
            return "기본 캘린더를 찾지 못했어요. 캘린더 앱에서 기본 캘린더를 지정해 주세요."
        case .missingIdentifier:
            return "캘린더 저장 결과를 확인하지 못했어요."
        }
    }
}
