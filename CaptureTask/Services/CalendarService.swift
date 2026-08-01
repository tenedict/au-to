import EventKit
import Foundation

/// Apple 캘린더는 **출력**이지 원장이 아니다.
///
/// 할 일의 소유권은 언제나 앱에 있다. 캘린더 쓰기가 실패해도 할 일은 저장된 상태로 남는다
/// (AGENTS 규칙 6). 그래서 이 서비스는 저장 성공/실패만 돌려주고 상태를 갖지 않는다.
@MainActor
final class CalendarService {
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

    var errorDescription: String? {
        switch self {
        case .missingDate:
            return "날짜가 없어 캘린더에 추가할 수 없어요."
        case .accessDenied:
            return "캘린더 접근이 꺼져 있어요. 설정 > CaptureTask에서 접근을 허용해 주세요."
        case .missingCalendar:
            return "기본 캘린더를 찾지 못했어요. 캘린더 앱에서 기본 캘린더를 지정해 주세요."
        case .missingIdentifier:
            return "캘린더 저장 결과를 확인하지 못했어요."
        }
    }
}
